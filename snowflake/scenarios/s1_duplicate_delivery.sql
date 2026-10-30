-- =============================================================================
-- SCENARIO 1 : DUPLICATE DELIVERY
-- Goal: deliver the SAME transaction file twice (different path = Snowflake sees
--       a "new" file) and show positions are NOT double counted.
-- =============================================================================
USE ROLE ROLE_INGEST; USE DATABASE ASSET_MGMT; USE WAREHOUSE WH_PIPELINE;

-- 1. BEFORE: note the counts
SELECT COUNT(*) AS raw_txn_rows_before FROM RAW.TRANSACTIONS;      -- expect 20

-- 2. Re-deliver the identical file under a different stage folder (run in SnowSQL):
--    PUT file://data/transactions.csv @RAW.LANDING_STAGE/transactions_redelivery/ AUTO_COMPRESS=FALSE;

COPY INTO RAW.TRANSACTIONS
  (transaction_id, portfolio_id, security_id, trade_date, txn_type, quantity, price, currency, _source_file, _source_row)
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE/transactions_redelivery/)
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT') ON_ERROR = ABORT_STATEMENT;

-- 3. RAW now holds every row twice (raw is append-only, nothing is lost)
SELECT COUNT(*) AS raw_txn_rows_after FROM RAW.TRANSACTIONS;       -- expect 40

-- 4. Re-run the pipeline (shell):   cd dbt && dbt build
-- 5. Then check as ROLE_TRANSFORM. Expect: accepted still 12, duplicates now 21,
--    and ZERO rows in the BREAK query -> positions are not double counted.
USE ROLE ROLE_TRANSFORM;
SELECT dq_status, COUNT(*) FROM SILVER.SILVER_TRANSACTIONS GROUP BY 1;       -- ACCEPTED 12 | DUPLICATE 21 | REJECTED 7
SELECT * FROM GOLD.GOLD_POSITION_VS_TRANSACTIONS WHERE status = 'BREAK';     -- expect 0 rows
SELECT * FROM GOLD.GOLD_RUN_RECONCILIATION WHERE dataset = 'transactions';   -- received 40 = 12 + 7 + 21
