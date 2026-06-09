-- ============================================================
-- Example 1: Owner's Rights — Privilege Delegation
-- ============================================================
-- Demonstrates: EXECUTE AS OWNER stored procedure
-- Concept: The DATA_ENGINEER role owns sensitive order data.
--          The ANALYST role can run a controlled operation via
--          the procedure WITHOUT needing direct DELETE access.
--
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- Requires: ACCOUNTADMIN to set up roles and grants
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS data_engineer_role;
CREATE ROLE IF NOT EXISTS analyst_role;
GRANT ROLE data_engineer_role TO ROLE ACCOUNTADMIN;
GRANT ROLE analyst_role TO ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS executor_demo;
CREATE SCHEMA IF NOT EXISTS executor_demo.tpch;

-- Give data_engineer access to the source data
GRANT USAGE ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE data_engineer_role;
GRANT USAGE ON SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 TO ROLE data_engineer_role;
GRANT SELECT ON TABLE SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS TO ROLE data_engineer_role;

-- Give data_engineer ownership of the demo schema
GRANT USAGE ON DATABASE executor_demo TO ROLE data_engineer_role;
GRANT ALL ON SCHEMA executor_demo.tpch TO ROLE data_engineer_role;

-- Analyst gets no access to source data -- only the proc
GRANT USAGE ON DATABASE executor_demo TO ROLE analyst_role;
GRANT USAGE ON SCHEMA executor_demo.tpch TO ROLE analyst_role;

-- Create the proc as data_engineer (owner's rights by default)
USE ROLE data_engineer_role;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE PROCEDURE executor_demo.tpch.high_value_orders(min_price FLOAT)
  RETURNS TABLE (order_key NUMBER, total_price FLOAT, status VARCHAR)
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
BEGIN
  RETURN TABLE(
    SELECT o_orderkey, o_totalprice, o_orderstatus
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
    WHERE o_totalprice > :min_price
    ORDER BY o_totalprice DESC
    LIMIT 10
  );
END;

GRANT USAGE ON PROCEDURE executor_demo.tpch.high_value_orders(FLOAT) TO ROLE analyst_role;

-- === DEMONSTRATE: analyst calls the proc and gets data ===
USE ROLE analyst_role;
USE WAREHOUSE COMPUTE_WH;

CALL executor_demo.tpch.high_value_orders(500000);
-- Expected: 10 rows of high-value orders
-- The analyst has NO direct access to TPCH_SF1.ORDERS -- but the proc owner does

-- === CONTRAST: analyst queries the table directly ===
SELECT o_orderkey, o_totalprice
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 5;
-- Expected: SQL access control error: privilege [SELECT] not granted

-- === CLEANUP ===
USE ROLE ACCOUNTADMIN;
DROP PROCEDURE IF EXISTS executor_demo.tpch.high_value_orders(FLOAT);
DROP ROLE IF EXISTS analyst_role;
DROP ROLE IF EXISTS data_engineer_role;
DROP DATABASE IF EXISTS executor_demo;

-- ============================================================
-- Cleanup (run after you're done with this example)
-- ============================================================
-- See .cortex/skills/executor-role-workshop/cleanup/SKILL.md
-- or run: $executor-role-workshop cleanup
-- ============================================================
