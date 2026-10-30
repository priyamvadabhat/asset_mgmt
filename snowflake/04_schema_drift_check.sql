-- =============================================================================
-- 04_schema_drift_check.sql  |  Run as ROLE_INGEST BEFORE every load
-- Compares the header of the staged files with the contract we expect.
-- Any row with header_ok = FALSE  =>  STOP, do not COPY, raise an alert.
-- (COPY would otherwise silently ignore extra trailing columns.)
-- =============================================================================
USE ROLE ROLE_INGEST;
USE DATABASE ASSET_MGMT;
USE WAREHOUSE WH_PIPELINE;

WITH actual AS (
  SELECT 'security_master' AS dataset,
         LISTAGG(LOWER(column_name), ',') WITHIN GROUP (ORDER BY order_id) AS cols
  FROM TABLE(INFER_SCHEMA(LOCATION => '@RAW.LANDING_STAGE/security_master/', FILE_FORMAT => 'RAW.CSV_HEADER_FMT'))
  UNION ALL
  SELECT 'transactions',
         LISTAGG(LOWER(column_name), ',') WITHIN GROUP (ORDER BY order_id)
  FROM TABLE(INFER_SCHEMA(LOCATION => '@RAW.LANDING_STAGE/transactions/', FILE_FORMAT => 'RAW.CSV_HEADER_FMT'))
  UNION ALL
  SELECT 'positions',
         LISTAGG(LOWER(column_name), ',') WITHIN GROUP (ORDER BY order_id)
  FROM TABLE(INFER_SCHEMA(LOCATION => '@RAW.LANDING_STAGE/positions/', FILE_FORMAT => 'RAW.CSV_HEADER_FMT'))
  UNION ALL
  SELECT 'market_prices',
         LISTAGG(LOWER(column_name), ',') WITHIN GROUP (ORDER BY order_id)
  FROM TABLE(INFER_SCHEMA(LOCATION => '@RAW.LANDING_STAGE/market_prices/', FILE_FORMAT => 'RAW.CSV_HEADER_FMT'))
  UNION ALL
  SELECT 'restricted_securities',
         LISTAGG(LOWER(column_name), ',') WITHIN GROUP (ORDER BY order_id)
  FROM TABLE(INFER_SCHEMA(LOCATION => '@RAW.LANDING_STAGE/restricted_securities/', FILE_FORMAT => 'RAW.CSV_HEADER_FMT'))
),
expected AS (
  SELECT 'security_master' AS dataset, 'security_id,isin,asset_class,currency,effective_from,effective_to' AS cols
  UNION ALL SELECT 'transactions', 'transaction_id,portfolio_id,security_id,trade_date,txn_type,quantity,price,currency'
  UNION ALL SELECT 'positions', 'portfolio_id,security_id,position_date,quantity,book_value,currency'
  UNION ALL SELECT 'market_prices', 'security_id,price_date,price,price_currency,price_source'
  UNION ALL SELECT 'restricted_securities', 'security_id,restriction_type,effective_from,effective_to,status'
)
SELECT e.dataset, e.cols AS expected_columns, a.cols AS actual_columns,
       (e.cols = a.cols) AS header_ok
FROM expected e LEFT JOIN actual a USING (dataset);
