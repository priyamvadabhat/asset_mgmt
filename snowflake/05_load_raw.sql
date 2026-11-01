-- =============================================================================
-- 05_load_raw.sql  |  Run as ROLE_INGEST

-- Step 2: COPY INTO RAW tables
-- =============================================================================
USE ROLE ROLE_INGEST;
USE DATABASE ASSET_MGMT;
USE WAREHOUSE WH_PIPELINE;


-- File-level idempotency: Snowflake remembers which staged files it has already
-- loaded (64 days) and skips them, so re-running this script is a no-op.
-- ON_ERROR = ABORT_STATEMENT: a bad file loads NOTHING (no partial load).
-- METADATA$FILENAME / METADATA$FILE_ROW_NUMBER = record-level lineage.

COPY INTO RAW.SECURITY_MASTER
  (security_id, isin, asset_class, currency, effective_from, effective_to, _source_file, _source_row)
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE)
PATTERN = '^security_master.*\.csv$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT')
ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.TRANSACTIONS
  (transaction_id, portfolio_id, security_id, trade_date, txn_type, quantity, price, currency, _source_file, _source_row)
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE)
PATTERN = '^transactions.*\.csv$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT')
ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.POSITIONS
  (portfolio_id, security_id, position_date, quantity, book_value, currency, _source_file, _source_row)
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE)
PATTERN = '^positions.*\.csv$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT')
ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.MARKET_PRICES
  (security_id, price_date, price, price_currency, price_source, _source_file, _source_row)
FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE)
PATTERN = '^market_prices.*\.csv$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT')
ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.RESTRICTED_SECURITIES
  (security_id, restriction_type, effective_from, effective_to, status, _source_file, _source_row)
FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @RAW.LANDING_STAGE)
PATTERN = '^restricted_securities.*\.csv$'
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT')
ON_ERROR = ABORT_STATEMENT;

-- Quick check: row counts per source file (should equal CSV line count - 1)
SELECT 'transactions' AS dataset, _source_file, COUNT(*) AS n FROM RAW.TRANSACTIONS GROUP BY 2
UNION ALL SELECT 'positions', _source_file, COUNT(*) FROM RAW.POSITIONS GROUP BY 2
UNION ALL SELECT 'market_prices', _source_file, COUNT(*) FROM RAW.MARKET_PRICES GROUP BY 2
UNION ALL SELECT 'security_master', _source_file, COUNT(*) FROM RAW.SECURITY_MASTER GROUP BY 2
UNION ALL SELECT 'restricted_securities', _source_file, COUNT(*) FROM RAW.RESTRICTED_SECURITIES GROUP BY 2;


SHOW TABLES IN SCHEMA ASSET_MGMT.SILVER;

SHOW TABLES IN SCHEMA ASSET_MGMT.GOLD;

select * from asset_mgmt.silver.silver_transactions;
