-- =============================================================================
-- 03_masking_and_grants.sql  |  Run as ACCOUNTADMIN (once, after 02)
-- Column masking + grants on the RAW/AUDIT objects created in 02.
-- =============================================================================
USE DATABASE ASSET_MGMT;

-- ---- Masking policy on ISIN -------------------------------------------------
-- Analysts see ******1234 ; Compliance / pipeline roles see the full value.
-- dbt re-applies this to GOLD.GOLD_PORTFOLIO_POSITIONS after each rebuild
-- (see the post_hook in that model).
CREATE OR REPLACE MASKING POLICY AUDIT.MASK_ISIN AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('ROLE_COMPLIANCE', 'ROLE_TRANSFORM', 'ACCOUNTADMIN') THEN val
    ELSE REGEXP_REPLACE(val, '.(?=.{4})', '*')
  END;

-- dbt (ROLE_TRANSFORM) must be allowed to attach the policy to tables it builds.
GRANT APPLY ON MASKING POLICY AUDIT.MASK_ISIN TO ROLE ROLE_TRANSFORM;

-- ---- Grants on RAW ----------------------------------------------------------
-- Ingest role: write RAW tables + use stage/file formats. Nothing else.
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA RAW TO ROLE ROLE_INGEST;
GRANT READ, WRITE ON STAGE RAW.LANDING_STAGE TO ROLE ROLE_INGEST;
GRANT USAGE ON FILE FORMAT RAW.CSV_FMT TO ROLE ROLE_INGEST;
GRANT USAGE ON FILE FORMAT RAW.CSV_HEADER_FMT TO ROLE ROLE_INGEST;

-- Transform role: read-only on RAW (it can never alter source data).
GRANT SELECT ON ALL TABLES IN SCHEMA RAW TO ROLE ROLE_TRANSFORM;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW TO ROLE ROLE_TRANSFORM;

-- Transform role writes the audit tables.
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA AUDIT TO ROLE ROLE_TRANSFORM;

-- ---- Auditable activity ------------------------------------------------------
-- Snowflake records every query automatically:
--   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY   (who ran what, when)
--   SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY  (which columns were read) [Enterprise]
--   SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
-- See snowflake/queries/demo_queries.sql for an example audit query.
