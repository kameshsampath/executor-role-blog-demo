-- ============================================================
-- Example 3: Dynamic Table — EXECUTE AS USER
-- ============================================================
-- Demonstrates: Dynamic table execution context
-- Concept: Dynamic tables default to SYSTEM user context.
--          CURRENT_USER() returns SYSTEM inside the table body.
--          EXECUTE AS USER pins a named user as execution identity.
--
-- Uses: executor_demo database (created in Example 1)
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS transform_role;
GRANT ROLE transform_role TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE transform_role;

-- Create a service user to pin the refresh identity
CREATE USER IF NOT EXISTS svc_transform
  DEFAULT_ROLE = transform_role
  MUST_CHANGE_PASSWORD = FALSE;
GRANT ROLE transform_role TO USER svc_transform;

-- Give the owner role IMPERSONATE on the service user
GRANT IMPERSONATE ON USER svc_transform TO ROLE transform_role;

CREATE DATABASE IF NOT EXISTS executor_demo;
CREATE SCHEMA IF NOT EXISTS executor_demo.tpch;
GRANT USAGE ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE transform_role;
GRANT USAGE ON SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 TO ROLE transform_role;
GRANT SELECT ON TABLE SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM TO ROLE transform_role;
GRANT USAGE ON DATABASE executor_demo TO ROLE transform_role;
GRANT ALL ON SCHEMA executor_demo.tpch TO ROLE transform_role;

USE ROLE transform_role;
USE WAREHOUSE COMPUTE_WH;

-- Create a masking policy that checks the current user
CREATE OR REPLACE MASKING POLICY executor_demo.tpch.mask_price AS
(val FLOAT) RETURNS FLOAT ->
CASE
  WHEN CURRENT_USER() = 'SVC_TRANSFORM' THEN val
  ELSE -1
END;

-- Base table with the policy applied
CREATE OR REPLACE TABLE executor_demo.tpch.lineitem_prices AS
SELECT l_orderkey, l_extendedprice, l_discount
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
LIMIT 1000;

ALTER TABLE executor_demo.tpch.lineitem_prices
  MODIFY COLUMN l_extendedprice
  SET MASKING POLICY executor_demo.tpch.mask_price;

-- === DEMONSTRATE: dynamic table WITH EXECUTE AS USER ===
CREATE OR REPLACE DYNAMIC TABLE executor_demo.tpch.dt_revenue
  TARGET_LAG = '1 hour'
  WAREHOUSE = COMPUTE_WH
  EXECUTE AS USER svc_transform
AS
  SELECT l_orderkey,
         SUM(l_extendedprice * (1 - l_discount)) AS net_revenue
  FROM executor_demo.tpch.lineitem_prices
  GROUP BY l_orderkey;

ALTER DYNAMIC TABLE executor_demo.tpch.dt_revenue REFRESH;
-- Expected: refresh completes, data shows real prices (CURRENT_USER = SVC_TRANSFORM)

SELECT * FROM executor_demo.tpch.dt_revenue LIMIT 5;
-- Expected: net_revenue shows real numbers, not -1

-- === CONTRAST: without EXECUTE AS USER ===
-- If you create the same DT without EXECUTE AS USER, the refresh runs as SYSTEM.
-- CURRENT_USER() != 'SVC_TRANSFORM' so the masking policy returns -1 for all rows.
-- The DT refreshes successfully but all revenue values are -1.

-- === CLEANUP ===
USE ROLE ACCOUNTADMIN;
DROP DYNAMIC TABLE IF EXISTS executor_demo.tpch.dt_revenue;
DROP TABLE IF EXISTS executor_demo.tpch.lineitem_prices;
DROP MASKING POLICY IF EXISTS executor_demo.tpch.mask_price;
DROP USER IF EXISTS svc_transform;
REVOKE IMPERSONATE ON USER svc_transform FROM ROLE transform_role;
DROP ROLE IF EXISTS transform_role;
DROP DATABASE IF EXISTS executor_demo;

-- ============================================================
-- Cleanup (run after you're done with this example)
-- ============================================================
-- See .cortex/skills/executor-role-workshop/cleanup/SKILL.md
-- or run: $executor-role-workshop cleanup
-- ============================================================
