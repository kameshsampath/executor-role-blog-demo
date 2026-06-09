-- ============================================================
-- Example 4: Masking Policy — INVOKER_ROLE()
-- ============================================================
-- Demonstrates: INVOKER_ROLE() in a masking policy body
-- Concept: INVOKER_ROLE() inside a masking policy returns the
--          role of the user querying the masked column.
--          Use this to enforce access by the querying user's role.
--
-- Key rule: Use INVOKER_ROLE() to enforce by object ownership.
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS analyst_role;
CREATE ROLE IF NOT EXISTS view_creator_role;
GRANT ROLE analyst_role TO ROLE ACCOUNTADMIN;
GRANT ROLE view_creator_role TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE analyst_role;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE view_creator_role;

CREATE DATABASE IF NOT EXISTS executor_demo;
CREATE SCHEMA IF NOT EXISTS executor_demo.tpch;
GRANT USAGE ON DATABASE executor_demo TO ROLE analyst_role;
GRANT USAGE ON SCHEMA executor_demo.tpch TO ROLE analyst_role;
GRANT USAGE ON DATABASE executor_demo TO ROLE view_creator_role;
GRANT ALL ON SCHEMA executor_demo.tpch TO ROLE view_creator_role;

GRANT USAGE ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE view_creator_role;
GRANT USAGE ON SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 TO ROLE view_creator_role;
GRANT SELECT ON TABLE SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS TO ROLE view_creator_role;

-- Create the masking policy using INVOKER_ROLE
CREATE OR REPLACE MASKING POLICY executor_demo.tpch.mask_order_price AS
(val FLOAT) RETURNS FLOAT ->
CASE
  WHEN INVOKER_ROLE() = 'ANALYST_ROLE' THEN val
  ELSE -1
END;

-- Create a base table and apply the policy
USE ROLE view_creator_role;
CREATE OR REPLACE TABLE executor_demo.tpch.orders_sample AS
SELECT o_orderkey, o_custkey, o_totalprice, o_orderstatus
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 100;

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON TABLE executor_demo.tpch.orders_sample TO ROLE analyst_role;
GRANT SELECT ON TABLE executor_demo.tpch.orders_sample TO ROLE view_creator_role;
GRANT ALL ON TABLE executor_demo.tpch.orders_sample TO ROLE view_creator_role;

ALTER TABLE executor_demo.tpch.orders_sample
  MODIFY COLUMN o_totalprice
  SET MASKING POLICY executor_demo.tpch.mask_order_price;

-- Create a view owned by view_creator_role (NOT analyst_role)
USE ROLE view_creator_role;
CREATE OR REPLACE VIEW executor_demo.tpch.orders_view AS
SELECT * FROM executor_demo.tpch.orders_sample;

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON VIEW executor_demo.tpch.orders_view TO ROLE analyst_role;

-- === DEMONSTRATE: analyst queries the table directly ===
USE ROLE analyst_role;
USE WAREHOUSE COMPUTE_WH;

SELECT o_orderkey, o_totalprice FROM executor_demo.tpch.orders_sample LIMIT 5;
-- Expected: real prices (INVOKER_ROLE = ANALYST_ROLE, policy returns val)

-- === CONTRAST: analyst queries through the view ===
SELECT o_orderkey, o_totalprice FROM executor_demo.tpch.orders_view LIMIT 5;
-- Expected: -1 for all prices (INVOKER_ROLE = VIEW_CREATOR_ROLE, not ANALYST_ROLE)
-- The analyst's session role is ANALYST_ROLE -- but INVOKER_ROLE returns VIEW_CREATOR_ROLE

-- === CLEANUP ===
USE ROLE ACCOUNTADMIN;
DROP VIEW IF EXISTS executor_demo.tpch.orders_view;
DROP TABLE IF EXISTS executor_demo.tpch.orders_sample;
DROP MASKING POLICY IF EXISTS executor_demo.tpch.mask_order_price;
DROP ROLE IF EXISTS analyst_role;
DROP ROLE IF EXISTS view_creator_role;
DROP DATABASE IF EXISTS executor_demo;

-- ============================================================
-- Cleanup (run after you're done with this example)
-- ============================================================
-- See .cortex/skills/executor-role-workshop/cleanup/SKILL.md
-- or run: $executor-role-workshop cleanup
-- ============================================================
