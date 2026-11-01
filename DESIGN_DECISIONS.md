# Design Decisions 


## 0. Assumptions
- Daily full-file deliveries, one business date at a time (`business_date` var, default 2026-10-29).
- Only the five brief datasets; I added `txn_type` (BUY/SELL) to transactions - to calculate a BUY_BAN 
- Valuation is in **local currency** (market value = quantity x price). No FX table was supplied; b
- A restriction (cant trade during a particular period) counts only if `status = ACTIVE` **and** the trade date is inside its window. `TRADING_BAN` blocks all trades, `BUY_BAN` blocks BUYs only. A `LIFTED` restriction is ignored even though the trade falls between the dates. (T1009). (For future improvement, lifted_date can be added)
- Positions are a reported snapshot. Transactions are *not* used to build positions; they are used to **check** them (`GOLD_POSITION_VS_TRANSACTIONS`), because the sample positions include balances with no trade history.

## 1. Keys
| Dataset | Business key | Why |
|---|---|---|
| Security master | `security_id` + `effective_from` | one row per version (SEC006 has two) |
| Transactions | `transaction_id` | trade identifier from source |
| Positions | `portfolio_id` + `security_id` + `position_date` | identified one holding uniquely |
| Market prices | `security_id` + `price_date` + `price_source` | multiple vendors may quote the same security same day |
| Restrictions | `security_id` + `restriction_type` + `effective_from` | |

Rows with a missing key part cannot be de-duplicated safely, so they are rejected and each is treated as unique (key falls back to file+row) so none is hidden as a "duplicate".

## 2. Idempotency, duplicates, corrections, reruns
Two layers:
1. **File level** - `COPY INTO` tracks loaded files and skips them; re-running the load is a no-op. A failed COPY loads nothing (`ON_ERROR=ABORT_STATEMENT`).
2. **Record level** - Bronze is **append-only** (a re-delivery under another name just adds rows). Silver keeps one row per business key via `row_number() ... order by _loaded_at desc`; the rest become `DUPLICATE` and are counted in reconciliation. **Latest delivery wins**, which is also how a corrected record replaces an earlier one.
3. **Rerun safe** - For simplicity sake, I have made every Silver/Gold model is a full rebuild from Bronze, so running `dbt build` twice gives identical output, and a failed run is repaired by simply running it again. Business-date reruns use `--vars '{business_date: ...}'`.



## 3. Late data and schema evolution
- **Late data:** Bronze keeps arrival time (`_loaded_at`). A late price or transaction is loaded, the pipeline reruns for the business date, and the output self-heals (a quarantined position is published). Past dates are corrected by rerunning with that `business_date`.
- **Schema change:** raw columns are VARCHAR so type drift lands and is quarantined. Structural drift is caught by (a) `ERROR_ON_COLUMN_COUNT_MISMATCH` (file refused, nothing loaded) and (b) `04_schema_drift_check.sql` comparing headers to the contract *before* COPY, because positional `$n` loading would silently ignore an extra column. Additive columns need a deliberate DDL + model change; 

## 4. Security
- **Least privilege:** `ROLE_INGEST` (write RAW only), `ROLE_TRANSFORM` (read RAW, write Silver/Gold/Audit - it cannot modify source data), `ROLE_ANALYST` / `ROLE_COMPLIANCE` (read Gold only).
- **Protected data:** masking policy on ISIN (re-applied by a dbt post-hook since tables are rebuilt); analysts cannot read Silver/Bronze/quarantine.
- **Secrets:** credentials only in environment variables; `profiles.yml` and key files are git-ignored. Production: key-pair/SSO auth, secrets manager, external stage with a storage integration.
- **Auditable:** Snowflake `QUERY_HISTORY`/`ACCESS_HISTORY`, plus our own `AUDIT.PIPELINE_RUN_LOG` and every Gold row stamped with `run_id`.

## 5. Observability, failure and recovery
- **Run log** (`on-run-end` hook) records SUCCESS/FAILED, node counts, even when a model fails.
- **Reconciliation:** received (from Bronze) = accepted + rejected + duplicates per dataset, stored per run in history to show trends; business metrics (exceptions, withheld positions, quarantine size).
- **Freshness/volume:** `dbt source freshness` (warn 24h / error 72h); reject-rate test as a volume/quality proxy.
- **Alerting:** `dbt build` returns non-zero on failure, so any scheduler can alert; WARN tests surface in output. Production: route to Slack/PagerDuty and add row-count anomaly checks against history.
- **No silent loss / partial publication:** Bronze is never altered; `dbt build` stops downstream models when a model or error-severity test fails; replay = rerun. **Limitation:** `CREATE OR REPLACE TABLE` per model is atomic *per table*, not across tables, so after a failure Gold tables may come from different runs (visible via `run_id`) until the rerun. Production fix: build into a staging schema and `ALTER SCHEMA ... SWAP WITH` only after all tests pass.

## 6. Scaling
**Likely bottleneck:** every run reprocesses all history - window functions (`row_number` partitioned by key) and the effective-date range joins over the full Bronze tables. Cost grows with *total* history, not daily volume. The range join is the first thing to watch 

**Plan:** (1) measure with the generator at 10k / 100k / 1M+ transactions; (2) make Silver/Gold *incremental* (merge on business key, process only new/changed `_loaded_at` and the affected business date); (3) cluster large tables by date/key; (4) scale warehouse size only if queries spill (check `bytes_spilled`); (5) for the effective-date join, pre-expand security master to a daily/versioned dimension; (6) Snowpipe/Dynamic Tables if latency matters.


## 7. Known limitations
- Quarantine is rebuilt each run (no history of past rejects); the reject *counts* are kept in audit history.
- Duplicate-detection uses the latest-wins rule described above.
