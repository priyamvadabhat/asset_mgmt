-- =============================================================================
-- SCENARIO 3 : RESTRICTED SECURITY
-- The sample data already contains the scenario - just look at the output.
--   T1005 PF002 BUY SEC004 on 2026-10-12  (TRADING_BAN 2026-10-05..2026-10-20) -> EXCEPTION
--   T1007 PF003 BUY SEC005 on 2026-10-14  (BUY_BAN from 2026-10-01, open ended) -> EXCEPTION
--   T1006 SEC004 on 2026-10-22 -> ban already ended           -> no exception
--   T1008 SELL SEC005          -> BUY_BAN does not block sells -> no exception
--   T1009 SEC006 on 2026-09-15 -> restriction status LIFTED   -> no exception
-- =============================================================================
USE ROLE ROLE_TRANSFORM; USE DATABASE ASSET_MGMT; USE WAREHOUSE WH_PIPELINE;

SELECT * FROM GOLD.GOLD_COMPLIANCE_EXCEPTIONS ORDER BY trade_date;

-- Automated check: dbt test --select tag:sample_data
