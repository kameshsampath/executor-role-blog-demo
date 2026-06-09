-- ============================================================
-- Example 5: Masking Policy — CURRENT_ROLE() / Caller's Rights
-- ============================================================
-- Demonstrates: Interaction between caller's-rights procedures
--               and masking policy context functions
-- Concept: CURRENT_ROLE() reflects session identity.
--          Through a caller's-rights procedure, the masking
--          policy evaluates the procedure caller's role —
--          not the policy owner's role.
--
-- Key rule: Use CURRENT_ROLE() to enforce by session identity.
--           INVOKER_ROLE() and CURRENT_ROLE() are not interchangeable.
-- ============================================================

-- === SETUP ===
-- Run 04-masking-invoker-role.sql first (or re-run setup below)
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

-- Create a base table
USE ROLE view_creator_role;
CREATE OR REPLACE TABLE executor_demo.tpch.orders_sample AS
SELECT o_orderkey, o_custkey, o_totalprice, o_orderstatus
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 100;

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON TABLE executor_demo.tpch.orders_sample TO ROLE analyst_role;
GRANT SELECT ON TABLE executor_demo.tpch.orders_sample TO ROLE view_creator_role;
GRANT ALL ON TABLE executor_demo.tpch.orders_sample TO ROLE view_creator_role;

-- Create a view owned by view_creator_role
USE ROLE view_creator_role;
CREATE OR REPLACE VIEW executor_demo.tpch.orders_view AS
SELECT * FROM executor_demo.tpch.orders_sample;

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON VIEW executor_demo.tpch.orders_view TO ROLE analyst_role;

-- === FIX: use CURRENT_ROLE() instead of INVOKER_ROLE() ===
CREATE OR REPLACE MASKING POLICY executor_demo.tpch.mask_order_price AS
(val FLOAT) RETURNS FLOAT ->
CASE
  WHEN CURRENT_ROLE() = 'ANALYST_ROLE' THEN val
  ELSE -1
END;

ALTER TABLE executor_demo.tpch.orders_sample
  MODIFY COLUMN o_totalprice
  SET MASKING POLICY executor_demo.tpch.mask_order_price;

USE ROLE analyst_role;
SELECT o_orderkey, o_totalprice FROM executor_demo.tpch.orders_view LIMIT 5;
-- Expected: real prices (CURRENT_ROLE = ANALYST_ROLE regardless of view ownership)

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
