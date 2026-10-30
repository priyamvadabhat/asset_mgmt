-- =============================================================================
-- 01_setup.sql  |  Run as ACCOUNTADMIN (once)
-- Creates database, warehouse, medallion schemas and least-privilege roles.
-- =============================================================================

-- ---- 1. Database + warehouse ------------------------------------------------
CREATE DATABASE IF NOT EXISTS ASSET_MGMT;

-- Small warehouse, auto-suspends after 60s so an idle pipeline costs nothing.
CREATE WAREHOUSE IF NOT EXISTS WH_PIPELINE
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;

-- ---- 2. Medallion schemas ---------------------------------------------------
-- RAW    = Bronze : files exactly as received (all VARCHAR) + load metadata
-- SILVER = Silver : typed, validated, de-duplicated, effective-dated; every row
--                   carries a dq_status (ACCEPTED / REJECTED / DUPLICATE)
-- GOLD   = Gold   : trusted outputs for consumers (positions, compliance, recon)
-- AUDIT  = run log, reconciliation history, masking policy
CREATE SCHEMA IF NOT EXISTS ASSET_MGMT.RAW;
CREATE SCHEMA IF NOT EXISTS ASSET_MGMT.SILVER;
CREATE SCHEMA IF NOT EXISTS ASSET_MGMT.GOLD;
CREATE SCHEMA IF NOT EXISTS ASSET_MGMT.AUDIT;

-- ---- 3. Roles (least privilege) --------------------------------------------
-- ROLE_INGEST    : loads files into RAW only. Cannot read SILVER/GOLD.
-- ROLE_TRANSFORM : used by dbt. Reads RAW, writes SILVER/GOLD/AUDIT.
-- ROLE_ANALYST   : consumers. Reads GOLD only (ISIN is masked for this role).
-- ROLE_COMPLIANCE: like analyst but sees unmasked ISIN.
CREATE ROLE IF NOT EXISTS ROLE_INGEST;
CREATE ROLE IF NOT EXISTS ROLE_TRANSFORM;
CREATE ROLE IF NOT EXISTS ROLE_ANALYST;
CREATE ROLE IF NOT EXISTS ROLE_COMPLIANCE;

-- Warehouse + database usage
GRANT USAGE ON WAREHOUSE WH_PIPELINE TO ROLE ROLE_INGEST;
GRANT USAGE ON WAREHOUSE WH_PIPELINE TO ROLE ROLE_TRANSFORM;
GRANT USAGE ON WAREHOUSE WH_PIPELINE TO ROLE ROLE_ANALYST;
GRANT USAGE ON WAREHOUSE WH_PIPELINE TO ROLE ROLE_COMPLIANCE;
GRANT USAGE ON DATABASE ASSET_MGMT TO ROLE ROLE_INGEST;
GRANT USAGE ON DATABASE ASSET_MGMT TO ROLE ROLE_TRANSFORM;
GRANT USAGE ON DATABASE ASSET_MGMT TO ROLE ROLE_ANALYST;
GRANT USAGE ON DATABASE ASSET_MGMT TO ROLE ROLE_COMPLIANCE;

-- Ingest: RAW only
GRANT USAGE ON SCHEMA ASSET_MGMT.RAW TO ROLE ROLE_INGEST;

-- Transform: read RAW, own-write SILVER / GOLD / AUDIT
GRANT USAGE ON SCHEMA ASSET_MGMT.RAW TO ROLE ROLE_TRANSFORM;
GRANT ALL   ON SCHEMA ASSET_MGMT.SILVER TO ROLE ROLE_TRANSFORM;
GRANT ALL   ON SCHEMA ASSET_MGMT.GOLD   TO ROLE ROLE_TRANSFORM;
GRANT ALL   ON SCHEMA ASSET_MGMT.AUDIT  TO ROLE ROLE_TRANSFORM;

-- Consumers: GOLD only. Future grants cover tables dbt re-creates every run.
GRANT USAGE ON SCHEMA ASSET_MGMT.GOLD TO ROLE ROLE_ANALYST;
GRANT USAGE ON SCHEMA ASSET_MGMT.GOLD TO ROLE ROLE_COMPLIANCE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ASSET_MGMT.GOLD TO ROLE ROLE_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ASSET_MGMT.GOLD TO ROLE ROLE_COMPLIANCE;

-- Give the roles to the service user(s) / yourself. Replace the user names.
-- GRANT ROLE ROLE_INGEST    TO USER <your_user>;
-- GRANT ROLE ROLE_TRANSFORM TO USER <your_user>;
-- GRANT ROLE ROLE_ANALYST   TO USER <your_user>;
