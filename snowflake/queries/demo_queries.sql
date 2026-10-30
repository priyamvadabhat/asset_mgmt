-- =============================================================================
-- demo_queries.sql : reconciliation, lineage, quarantine, monitoring, audit
-- =============================================================================
USE ROLE ROLE_TRANSFORM; USE DATABASE ASSET_MGMT; USE WAREHOUSE WH_PIPELINE;

-- ---- 1. RUN RECONCILIATION (received = accepted + rejected + duplicates) ------
SELECT * FROM GOLD.GOLD_RUN_RECONCILIATION ORDER BY dataset;

-- ---- 2. KEY BUSINESS EXCEPTIONS / METRICS --------------------------------------
SELECT * FROM GOLD.GOLD_RUN_METRICS ORDER BY metric_name;

-- ---- 3. QUARANTINE: every untrusted record with reasons ---------------------------
SELECT dataset, record_key, reject_reasons, _source_file, _source_row
FROM SILVER.SILVER_QUARANTINE ORDER BY dataset, record_key;

-- ---- 4. RECORD-LEVEL LINEAGE: trace one published position back to its sources ----
-- From a Gold row -> the exact file + row of the position and of the price used.
SELECT portfolio_id, security_id, market_value,
       position_source_file, position_source_row,
       price_source, price_source_file, price_source_row, run_id
FROM GOLD.GOLD_PORTFOLIO_POSITIONS WHERE portfolio_id = 'PF001' AND security_id = 'SEC002';
-- ...then look at the raw record (still untouched in Bronze):
SELECT * FROM RAW.POSITIONS     WHERE _source_row = 2 AND _source_file LIKE '%positions.csv';
SELECT * FROM RAW.MARKET_PRICES WHERE security_id = 'SEC002';   -- both vendors visible; VENDOR_A was selected

-- ---- 5. LINEAGE of a compliance exception: transaction row + restriction row -----
SELECT transaction_id, restriction_type, transaction_source_file, transaction_source_row,
       restriction_source_file, restriction_source_row, run_id
FROM GOLD.GOLD_COMPLIANCE_EXCEPTIONS;

-- ---- 6. TEMPORAL LOGIC: SEC006 ISIN changed on 2026-10-01 ------------------------
SELECT portfolio_id, security_id, position_date, isin FROM GOLD.GOLD_PORTFOLIO_POSITIONS WHERE security_id = 'SEC006';
SELECT transaction_id, trade_date, isin_at_trade FROM SILVER.SILVER_TRANSACTIONS WHERE security_id = 'SEC006';

-- ---- 7. PIPELINE HEALTH: run history, trend of rejects ----------------------------
SELECT * FROM AUDIT.PIPELINE_RUN_LOG ORDER BY run_ts DESC LIMIT 10;
SELECT run_ts, dataset, records_received, rejected, duplicates
FROM AUDIT.RUN_RECONCILIATION_HISTORY ORDER BY run_ts DESC, dataset;

-- ---- 8. FRESHNESS: when did data last land? (also: dbt source freshness) ----------
SELECT 'transactions' AS dataset, MAX(_loaded_at) AS last_loaded, COUNT(*) AS rows_total FROM RAW.TRANSACTIONS
UNION ALL SELECT 'market_prices', MAX(_loaded_at), COUNT(*) FROM RAW.MARKET_PRICES
UNION ALL SELECT 'positions',     MAX(_loaded_at), COUNT(*) FROM RAW.POSITIONS;

-- ---- 9. SECURITY: masking + audit trail ---------------------------------------------
USE ROLE ROLE_ANALYST;
SELECT portfolio_id, security_id, isin, market_value FROM ASSET_MGMT.GOLD.GOLD_PORTFOLIO_POSITIONS LIMIT 5;  -- ISIN masked
-- Analyst cannot see Silver/Raw (expect "insufficient privileges"):
-- SELECT * FROM ASSET_MGMT.SILVER.SILVER_TRANSACTIONS;

USE ROLE ACCOUNTADMIN;  -- who ran what (audit)
SELECT user_name, role_name, query_type, start_time, LEFT(query_text, 80) AS query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE database_name = 'ASSET_MGMT' ORDER BY start_time DESC LIMIT 20;
