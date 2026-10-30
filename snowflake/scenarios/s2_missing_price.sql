-- =============================================================================
-- SCENARIO 2 : MISSING PRICE
-- Chosen behaviour:  QUARANTINE the position (do NOT publish it with a NULL/zero
-- market value), keep publishing every other position, raise a WARN test.
-- The supplied data already has two cases:
--   * PF002/SEC008 : latest price is 7 days old  -> STALE_PRICE  (quarantined)
--   * PF002/SEC007 : price is 1 day old          -> STALE_WARN   (published, flagged)
-- This script creates a third case: no price at all for SEC001.
-- =============================================================================
USE ROLE ACCOUNTADMIN; USE DATABASE ASSET_MGMT; USE WAREHOUSE WH_PIPELINE;

-- 1. Simulate the vendor not delivering SEC001's price (demo only - needs admin)
DELETE FROM RAW.MARKET_PRICES WHERE security_id = 'SEC001';

-- 2. Re-run the pipeline (shell):  cd dbt && dbt build
--    Expect: warn_quarantined_positions WARNS, build still succeeds.

-- 3. Check the effect on publication
USE ROLE ROLE_TRANSFORM;
SELECT * FROM GOLD.GOLD_PORTFOLIO_POSITIONS WHERE security_id = 'SEC001';           -- 0 rows (withheld)
SELECT * FROM SILVER.SILVER_QUARANTINE WHERE dataset = 'positions_pricing';         -- SEC001 MISSING_PRICE + SEC008 STALE_PRICE
SELECT * FROM GOLD.GOLD_RUN_METRICS WHERE metric_name LIKE 'positions_quarantined%';

-- 4. RESTORE: reload the file (FORCE re-loads a file Snowflake already knows)
USE ROLE ACCOUNTADMIN;
TRUNCATE TABLE RAW.MARKET_PRICES;
COPY INTO RAW.MARKET_PRICES
  (security_id, price_date, price, price_currency, price_source, _source_file, _source_row)
FROM (SELECT $1,$2,$3,$4,$5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RAW.LANDING_STAGE/market_prices/)
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FMT') FORCE = TRUE;
-- Re-run `dbt build`: SEC001 is published again automatically (late data self-heals).
