# Asset-Management Data Pipeline (Snowflake + dbt)

Ingest --> Validate --> Publish through Raw --> Silver --> Gold layers

Syntheic Asset management data (`docs/case_study_brief.pdf`).

Quarantine bad records like missing keys, duplicates, unknown securities, bad dates/prices.

Two Gold outputs : 
1. Trusted positions with market value & lineage metadata
2. Compliance exceptions (trades made during active restriction)

Validate:
Effective dated joins
Idempotent reruns
Run reconciliation and metrics (received, accepted, rejected, duplicates, key exceptions)

Pending validations:
Growing data behaviour
---

Future enhancements:
1. Currently a single source file is being read for this case study purpose. It needs to be enhanced, to read from bucket directly based on timestamps, or needs to be read from landing zone, based on what files need to be processed and what has already processed.


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

Prereqs: a Snowflake account (trial is fine), Python 3.9+, `pip install dbt-snowflake`.

