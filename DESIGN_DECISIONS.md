# Design Decisions 


## 0. Assumptions
- Daily full-file deliveries, one business date at a time (`business_date` var, default 2026-10-29).
- Only the five brief datasets; I added `txn_type` (BUY/SELL) to transactions - to calculate a BUY_BAN 
- Valuation is in **local currency** (market value = quantity x price). No FX table was supplied; base-currency reporting is a production addition.
- A restriction counts only if `status = ACTIVE` **and** the trade date is inside its window. `TRADING_BAN` blocks all trades, `BUY_BAN` blocks BUYs only. A `LIFTED` restriction is ignored even though its dates cover the trade (T1009).
- Positions are a reported snapshot. Transactions are *not* used to build positions; they are used to **check** them (`GOLD_POSITION_VS_TRANSACTIONS`), because the sample positions include balances with no trade history.

## 1. Keys
| Dataset | Business key | Why |
|---|---|---|
| Security master | `security_id` + `effective_from` | one row per version (SEC006 has two) |
| Transactions | `transaction_id` | trade identifier from source |
| Positions | `portfolio_id` + `security_id` + `position_date` | one holding per day |
| Market prices | `security_id` + `price_date` + `price_source` | two vendors may quote one day; choice made in Gold |
| Restrictions | `security_id` + `restriction_type` + `effective_from` | |

Rows with a missing key part cannot be de-duplicated safely, so they are rejected and each is treated as unique (key falls back to file+row) so none is hidden as a "duplicate".

## 2. Idempotency, duplicates, corrections, reruns
Two layers:
1. **File level** - `COPY INTO` tracks loaded files and skips them; re-running the load is a no-op. A failed COPY loads nothing (`ON_ERROR=ABORT_STATEMENT`).
2. **Record level** - Bronze is **append-only** (a re-delivery under another name just adds rows). Silver keeps one row per business key via `row_number() ... order by _loaded_at desc`; the rest become `DUPLICATE` and are counted in reconciliation. **Latest delivery wins**, which is also how a corrected record replaces an earlier one.
3. **Rerun safe** - every Silver/Gold model is a full rebuild from Bronze, so running `dbt build` twice gives identical output, and a failed run is repaired by simply running it again. Business-date reruns use `--vars '{business_date: ...}'`.

Trade-off: latest-wins means a *bad* correction replaces a *good* original (the original is then a duplicate and the new one quarantined). Alerts on reject rate and the quarantine make this visible; a production version would keep the last valid version.

## 3. Data-quality handling (reject vs quarantine vs warn)
| Condition | Behaviour | Effect on publication |
|---|---|---|
| Missing key, bad date/number, unknown security, currency mismatch | **Reject -> quarantine** with reason codes | Excluded from Gold; counted in recon |
| Duplicate | Marked `DUPLICATE`, counted | Excluded (original kept) |
| Price missing or older than 3 days | **Quarantine the position** (`silver_priced_positions`) | Position withheld; others still published; WARN test |
| Price 1-3 days old | **Warn**: publish with `STALE_WARN` | Published, flagged |
| Reject rate > 25% of a dataset | **Warn** test | Published; alert for a possible bad file |
| Reconciliation not balanced, duplicate in Gold, quantity BREAK | **Error** test | `dbt build` fails |

I chose to withhold unpriced positions rather than publish a zero/NULL market value: a wrong total silently flowing into valuation is worse than a visible gap. Nothing is deleted - every rejected record keeps its raw payload and file/row.

## 4. Temporal logic
Security-master joins use `trade_date`/`position_date`/`price_date` between `effective_from` and `effective_to` (open-ended = NULL), so the ISIN is the one valid on that date (SEC006) and a trade before a security existed is rejected (T1017). Restrictions use the same pattern.

## 5. Late data and schema evolution
- **Late data:** Bronze keeps arrival time (`_loaded_at`). A late price or transaction is loaded, the pipeline reruns for the business date, and the output self-heals (a quarantined position is published). Past dates are corrected by rerunning with that `business_date`.
- **Schema change:** raw columns are VARCHAR so type drift lands and is quarantined. Structural drift is caught by (a) `ERROR_ON_COLUMN_COUNT_MISMATCH` (file refused, nothing loaded) and (b) `04_schema_drift_check.sql` comparing headers to the contract *before* COPY, because positional `$n` loading would silently ignore an extra column. Additive columns need a deliberate DDL + model change; production would use schema evolution with review.

## 6. Security
- **Least privilege:** `ROLE_INGEST` (write RAW only), `ROLE_TRANSFORM` (read RAW, write Silver/Gold/Audit - it cannot modify source data), `ROLE_ANALYST` / `ROLE_COMPLIANCE` (read Gold only).
- **Protected data:** masking policy on ISIN (re-applied by a dbt post-hook since tables are rebuilt); analysts cannot read Silver/Bronze/quarantine.
- **Secrets:** credentials only in environment variables; `profiles.yml` and key files are git-ignored. Production: key-pair/SSO auth, secrets manager, external stage with a storage integration.
- **Auditable:** Snowflake `QUERY_HISTORY`/`ACCESS_HISTORY`, plus our own `AUDIT.PIPELINE_RUN_LOG` and every Gold row stamped with `run_id`.

## 7. Observability, failure and recovery
- **Run log** (`on-run-end` hook) records SUCCESS/FAILED, node counts, even when a model fails.
- **Reconciliation:** received (from Bronze) = accepted + rejected + duplicates per dataset, stored per run in history to show trends; business metrics (exceptions, withheld positions, quarantine size).
- **Freshness/volume:** `dbt source freshness` (warn 24h / error 72h); reject-rate test as a volume/quality proxy.
- **Alerting:** `dbt build` returns non-zero on failure, so any scheduler can alert; WARN tests surface in output. Production: route to Slack/PagerDuty and add row-count anomaly checks against history.
- **No silent loss / partial publication:** Bronze is never altered; `dbt build` stops downstream models when a model or error-severity test fails; replay = rerun. **Limitation:** `CREATE OR REPLACE TABLE` per model is atomic *per table*, not across tables, so after a failure Gold tables may come from different runs (visible via `run_id`) until the rerun. Production fix: build into a staging schema and `ALTER SCHEMA ... SWAP WITH` only after all tests pass.

## 8. Scaling
**Likely bottleneck:** every run reprocesses all history - window functions (`row_number` partitioned by key) and the effective-date range joins over the full Bronze tables. Cost grows with *total* history, not daily volume. The range join is the first thing to watch (not an equi-join).

**Plan:** (1) measure with the generator at 10k / 100k / 1M+ transactions; (2) make Silver/Gold *incremental* (merge on business key, process only new/changed `_loaded_at` and the affected business date); (3) cluster large tables by date/key; (4) scale warehouse size only if queries spill (check `bytes_spilled`); (5) for the effective-date join, pre-expand security master to a daily/versioned dimension; (6) Snowpipe/Dynamic Tables if latency matters.

**Measurements:** not collected - no Snowflake account was available during the build. Fill in after running scenario 5:

| Transactions | dbt build time | Slowest model | Spill? | Notes |
|---|---|---|---|---|
| 10,000 | | | | |
| 100,000 | | | | |
| 1,000,000 | | | | |

## 9. Known limitations
- Not executed against live Snowflake yet (see README).
- Overlapping effective-date ranges in the security master are not detected (would duplicate joined rows); add a test in production.
- Quarantine is rebuilt each run (no history of past rejects); the reject *counts* are kept in audit history.
- Duplicate-detection uses the latest-wins rule described above.
