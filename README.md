# Asset-Management Data Pipeline (Snowflake + dbt)

A small, working prototype that ingests five asset-management datasets, validates them,
quarantines bad records, and publishes trusted portfolio positions and compliance exceptions
- safely re-runnable, reconciled and traceable. Built for the *Engineering a Trusted Asset
Management Data Pipeline* case study (`docs/case_study_brief.pdf`).

**Stack:** Snowflake (storage + compute + security) and dbt (transformations + tests).
Kept deliberately simple: plain SQL, one model per step, comments on every section.

> **Status - please read:** the SQL has been written and reviewed but **not executed against a live
> Snowflake account** (none was available while building). "Expected results" below are derived by
> hand from the sample data. Please run it once and treat any Snowflake error as a bug to fix.
> No performance numbers are claimed (see Scaling).

---

## 1. Repo layout

```
data/                    synthetic input files (the 5 CSVs)
docs/                    case study PDF + architecture diagram (architecture.md)
snowflake/
  01_setup.sql           database, warehouse, schemas, roles (least privilege)
  02_raw_and_audit_tables.sql   stage, file formats, RAW + AUDIT tables
  03_masking_and_grants.sql     ISIN masking policy + grants
  04_schema_drift_check.sql     header contract check (run before every load)
  05_load_raw.sql        PUT + COPY INTO (file-level idempotent, all-or-nothing)
  scenarios/             s1..s5 = the five required validation scenarios
  queries/demo_queries.sql      reconciliation, lineage, quarantine, monitoring, audit
dbt/
  models/silver/         typed + validated + effective-dated + quarantine
  models/gold/           positions, compliance exceptions, checks, reconciliation, metrics
  tests/                 singular tests (recon balanced, no double count, warnings)
  macros/                run logging + schema naming
scripts/generate_volume_data.py   synthetic data for the volume test
DESIGN_DECISIONS.md      keys, idempotency, late data, schema evolution, security, monitoring, scaling
```

Medallion mapping: `RAW` (Bronze, as received) -> `SILVER` (validated) -> `GOLD` (trusted outputs). Diagram: [`docs/architecture.md`](docs/architecture.md).

## 2. Setup

Prereqs: a Snowflake account (trial is fine), SnowSQL or Snowsight, Python 3.9+, `pip install dbt-snowflake`.

```bash
# 1. Snowflake objects (run as ACCOUNTADMIN, in this order)
snowsql -f snowflake/01_setup.sql
snowsql -f snowflake/02_raw_and_audit_tables.sql
snowsql -f snowflake/03_masking_and_grants.sql
#    then: GRANT ROLE ROLE_INGEST / ROLE_TRANSFORM / ROLE_ANALYST TO USER <you>;

# 2. Upload the files (PUT commands are at the top of snowflake/05_load_raw.sql), then
snowsql -f snowflake/04_schema_drift_check.sql   # every header_ok must be TRUE
snowsql -f snowflake/05_load_raw.sql             # COPY INTO RAW

# 3. dbt credentials come from environment variables - nothing secret is in git
export SNOWFLAKE_ACCOUNT=<account> SNOWFLAKE_USER=<user> SNOWFLAKE_PASSWORD=<password>
cp dbt/profiles.yml.example ~/.dbt/profiles.yml
cd dbt && dbt debug
```

## 3. Run

```bash
cd dbt
dbt build                       # models + tests, in dependency order (stops bad data reaching Gold)
dbt test --select tag:sample_data   # checks the sample data gives the expected results
dbt source freshness            # has new data landed?
dbt build --vars '{business_date: 2026-10-30}'   # rerun for another business date
```
Then run `snowflake/queries/demo_queries.sql` for reconciliation, quarantine, lineage and audit views.

## 4. What the pipeline does (and expected result on the sample data)

| Step | What happens |
|---|---|
| Bronze | Files land untouched as VARCHAR + `_source_file`, `_source_row`, `_loaded_at`. |
| Silver | Typed with `try_to_*`; each row gets reason codes and `dq_status` = ACCEPTED / REJECTED / DUPLICATE. Security-master and restriction lookups are **effective-dated** (valid on the trade/position/price date). |
| Quarantine | `SILVER_QUARANTINE` holds every rejected record + reasons + original payload + lineage. |
| Gold | `GOLD_PORTFOLIO_POSITIONS` (market value + lineage), `GOLD_COMPLIANCE_EXCEPTIONS`, `GOLD_POSITION_VS_TRANSACTIONS`, `GOLD_RUN_RECONCILIATION`, `GOLD_RUN_METRICS`. |

**Validation rules (simple, per the brief):** missing keys; duplicates; unknown security (as of the date);
invalid or future dates; non-numeric / negative / zero quantity or price; bad txn type; currency mismatch;
stale or missing price; schema/header drift.

**Expected results on the supplied data (hand-derived):**

| Dataset | Received | Accepted | Rejected | Duplicates |
|---|---|---|---|---|
| security_master | 11 | 11 | 0 | 0 |
| transactions | 20 | 12 | 7 | 1 |
| positions | 12 | 11 | 0 | 1 |
| market_prices | 12 | 11 | 1 | 0 |
| restricted_securities | 3 | 3 | 0 | 0 |

Transaction rejects: T1013 missing portfolio, T1014 unknown security, T1015 negative price, T1016 invalid date,
T1017 SEC010 *not yet effective on the trade date* (temporal check), T1018 future trade date, T1019 non-numeric quantity.
T1004 is the duplicate. Price reject: SEC009 VENDOR_B price 0 (VENDOR_A price is used).

Positions on 2026-10-29: **10 published**, 1 withheld (PF002/SEC008: price 7 days old -> `STALE_PRICE`), 1 published with
a `STALE_WARN` flag (SEC007, 1 day old). SEC002 has two vendor prices - VENDOR_A wins by priority.
Compliance exceptions: **T1005** (SEC004 trading ban) and **T1007** (SEC005 buy ban). Not exceptions: T1006 (ban ended), T1008 (SELL under a BUY ban), T1009 (restriction LIFTED).
Position-vs-transaction check: 10 MATCH, 1 NO_TRANSACTIONS (PF004/SEC010 - its only trade was rejected), 0 BREAK.
`dbt build` ends with 2 expected **warnings**: transactions reject rate 35% (> 25%) and the quarantined position.

## 5. The five required scenarios

| # | Scenario | How to run | What you should see |
|---|---|---|---|
| 1 | Duplicate delivery | `snowflake/scenarios/s1_duplicate_delivery.sql` | Raw rows double (20 -> 40); accepted stays 12; 0 BREAK rows; recon balanced. |
| 2 | Missing price | `s2_missing_price.sql` | Position withheld from Gold, appears in quarantine, build still succeeds with a WARN; reloading the price publishes it. |
| 3 | Restricted security | `s3_restricted_security.sql` | T1005 and T1007 in `GOLD_COMPLIANCE_EXCEPTIONS` with transaction + restriction file/row lineage. |
| 4 | Mid-run failure | `s4_mid_run_failure.sql` | See below. |
| 5 | Volume increase | `s5_volume_test.sql` + `scripts/generate_volume_data.py` | Timings per size (fill in the table in DESIGN_DECISIONS.md). |

**Failure injection and replay**
```bash
cd dbt
dbt build                                  # 1. good run
dbt build --vars '{inject_failure: true}'  # 2. gold_compliance_exceptions fails; downstream skipped; non-zero exit
#    AUDIT.PIPELINE_RUN_LOG shows FAILED; RAW is untouched; Gold positions are still whole (single run_id)
dbt build                                  # 3. replay: same command, no cleanup -> SUCCESS, balanced
```
Schema-change test: add a column to a CSV header, PUT it, run `04_schema_drift_check.sql` -> `header_ok = FALSE` (do not COPY).

## 6. Implemented vs. what I would add for production

| Implemented here | Production additions |
|---|---|
| Layered Bronze/Silver/Gold, dq_status, quarantine | Incremental/merge models partitioned by business date; quarantine history table |
| File + record idempotency; business-date reruns | Orchestrator (Airflow / Snowflake Tasks), file-arrival triggers, blue/green schema swap for atomic publish |
| Reconciliation + run log + metrics history | Alert routing (Slack/PagerDuty), volume-anomaly checks vs. history, SLA dashboards |
| RBAC, masking, env-var secrets, query history audit | Key-pair/SSO auth, secrets manager, external stage + storage integration, row access policies, network policy |
| Tests + failure injection | CI (dbt build on a clone per PR), unit tests with seed data |
| Local-currency valuation | FX rates and base-currency reporting |
