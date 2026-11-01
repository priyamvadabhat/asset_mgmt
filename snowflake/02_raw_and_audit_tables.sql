-- =============================================================================
-- 02_raw_and_audit_tables.sql  |  Run as ACCOUNTADMIN (once)
-- Create RAW (Bronze) tables, stage, file formats and AUDIT tables.
-- =============================================================================
USE DATABASE ASSET_MGMT;
USE WAREHOUSE WH_PIPELINE;

-- ---- File formats -----------------------------------------------------------
-- Used for loading. Header is skipped; a column-count mismatch FAILS the load
-- (that is our schema-change guard).
CREATE OR REPLACE FILE FORMAT RAW.CSV_FMT
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  EMPTY_FIELD_AS_NULL = TRUE;

-- Used only by 04_schema_drift_check.sql to read the header row.
CREATE OR REPLACE FILE FORMAT RAW.CSV_HEADER_FMT
  TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"';

-- ---- Landing stage ----------------------------------------------------------
-- Internal stage (encrypted at rest). In production this would be an external
-- stage on S3/Azure/GCS via a STORAGE INTEGRATION (no keys in code).
CREATE STAGE IF NOT EXISTS RAW.LANDING_STAGE
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- ---- RAW tables -------------------------------------------------------------
-- Every business column is VARCHAR: bad data (e.g. quantity = 'abc') must LAND
-- so it can be quarantined and counted, never fail the load or vanish.
-- _source_file / _source_row / _loaded_at give record-level lineage.
CREATE TABLE IF NOT EXISTS RAW.SECURITY_MASTER (
  security_id VARCHAR, isin VARCHAR, asset_class VARCHAR, currency VARCHAR,
  effective_from VARCHAR, effective_to VARCHAR,
  _source_file VARCHAR, _source_row NUMBER,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW.TRANSACTIONS (
  transaction_id VARCHAR, portfolio_id VARCHAR, security_id VARCHAR,
  trade_date VARCHAR, txn_type VARCHAR, quantity VARCHAR, price VARCHAR, currency VARCHAR,
  _source_file VARCHAR, _source_row NUMBER,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW.POSITIONS (
  portfolio_id VARCHAR, security_id VARCHAR, position_date VARCHAR,
  quantity VARCHAR, book_value VARCHAR, currency VARCHAR,
  _source_file VARCHAR, _source_row NUMBER,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW.MARKET_PRICES (
  security_id VARCHAR, price_date VARCHAR, price VARCHAR,
  price_currency VARCHAR, price_source VARCHAR,
  _source_file VARCHAR, _source_row NUMBER,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW.RESTRICTED_SECURITIES (
  security_id VARCHAR, restriction_type VARCHAR,
  effective_from VARCHAR, effective_to VARCHAR, status VARCHAR,
  _source_file VARCHAR, _source_row NUMBER,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ---- AUDIT tables (written by dbt on-run-end hook) ---------------------------
-- One row per pipeline run: success/failure and node counts.
CREATE TABLE IF NOT EXISTS AUDIT.PIPELINE_RUN_LOG (
  run_id VARCHAR, run_ts TIMESTAMP_NTZ, business_date DATE, status VARCHAR,
  nodes_ok NUMBER, nodes_failed NUMBER, nodes_skipped NUMBER, dbt_command VARCHAR
);

-- History of per-dataset reconciliation (received/accepted/rejected/duplicates).
CREATE TABLE IF NOT EXISTS AUDIT.RUN_RECONCILIATION_HISTORY (
  run_id VARCHAR, run_ts TIMESTAMP_NTZ, business_date DATE, dataset VARCHAR,
  records_received NUMBER, accepted NUMBER, rejected NUMBER, duplicates NUMBER,
  is_balanced BOOLEAN
);

-- History of business-level metrics (exceptions, positions published, etc.).
CREATE TABLE IF NOT EXISTS AUDIT.RUN_METRICS_HISTORY (
  run_id VARCHAR, run_ts TIMESTAMP_NTZ, business_date DATE,
  metric_name VARCHAR, metric_value NUMBER
);
