-- =============================================================================
-- SCENARIO 4 : MID-RUN FAILURE + SAFE REPLAY
-- Failure is injected with a dbt variable (shell commands below).
-- =============================================================================
-- 1. Normal successful run first:         cd dbt && dbt build
--
-- 2. Inject the failure:                  dbt build --vars '{inject_failure: true}'
--    -> independent models may finish, but
--       gold_compliance_exceptions FAILS ("Numeric value 'INJECTED_FAILURE' ...").
--       dbt SKIPS everything downstream (gold_run_metrics, gold_run_reconciliation),
--       so no partial reconciliation is published. Exit code is non-zero (alert hook).
--
-- 3. Look at what the failure left behind:
USE ROLE ROLE_TRANSFORM; USE DATABASE ASSET_MGMT; USE WAREHOUSE WH_PIPELINE;
SELECT * FROM AUDIT.PIPELINE_RUN_LOG ORDER BY run_ts DESC LIMIT 3;   -- latest = FAILED, nodes_failed=1, nodes_skipped>0
SELECT run_id, COUNT(*) FROM GOLD.GOLD_PORTFOLIO_POSITIONS GROUP BY 1;   -- one run_id: no half-written rows
--    RAW is untouched (dbt only reads it), so nothing is lost.
--
-- 4. Replay (just rerun, no cleanup needed - every model is rebuilt from RAW):
--       dbt build
-- 5. Confirm recovery: latest run SUCCESS, same row counts as step 1, reconciliation balanced.
SELECT * FROM AUDIT.PIPELINE_RUN_LOG ORDER BY run_ts DESC LIMIT 3;
SELECT * FROM GOLD.GOLD_RUN_RECONCILIATION;
