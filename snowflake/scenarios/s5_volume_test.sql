-- =============================================================================
-- SCENARIO 5 : VOLUME INCREASE
-- 1. Generate data (shell):  python scripts/generate_volume_data.py --txns 10000 100000 1000000
-- 2. Clone the DB so the real data is untouched, then size the warehouse:
-- =============================================================================
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE DATABASE ASSET_MGMT_PERF CLONE ASSET_MGMT;
GRANT ALL ON DATABASE ASSET_MGMT_PERF TO ROLE ROLE_TRANSFORM;
GRANT ALL ON ALL SCHEMAS IN DATABASE ASSET_MGMT_PERF TO ROLE ROLE_TRANSFORM;
GRANT SELECT ON ALL TABLES IN SCHEMA ASSET_MGMT_PERF.RAW TO ROLE ROLE_TRANSFORM;

-- 3. For EACH size N:
--    a) replace the perf RAW data with the generated files
--         TRUNCATE TABLE ASSET_MGMT_PERF.RAW.TRANSACTIONS;  (same for POSITIONS)
--         PUT file://data/volume/transactions_<N>.csv @ASSET_MGMT_PERF.RAW.LANDING_STAGE/volume_<N>/ AUTO_COMPRESS=TRUE;
--         COPY INTO ASSET_MGMT_PERF.RAW.TRANSACTIONS ... FROM @.../volume_<N>/   (same statement as 05_load_raw.sql)
--    b) time the pipeline (shell):   time dbt build --target perf
--    c) per-model timings are in dbt/target/run_results.json, or here:
USE ROLE ACCOUNTADMIN;
SELECT query_text, total_elapsed_time/1000 AS seconds, bytes_scanned, partitions_scanned,
       bytes_spilled_to_local_storage
FROM TABLE(ASSET_MGMT_PERF.INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 200))
WHERE query_text ILIKE 'create or replace transient table%' OR query_text ILIKE 'create or replace table%'
ORDER BY start_time DESC;
-- 4. Record results in the table at the bottom of DESIGN_DECISIONS.md.
-- 5. Try ALTER WAREHOUSE WH_PIPELINE SET WAREHOUSE_SIZE = SMALL / MEDIUM and compare.
