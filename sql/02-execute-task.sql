-- ============================================================
-- Example 2: EXECUTE TASK — Account-Level Privilege
-- ============================================================
-- Demonstrates: Why tasks need EXECUTE TASK ON ACCOUNT
-- Concept: Tasks always run as their owner role. But triggering
--          a task also requires EXECUTE TASK — granted at the
--          ACCOUNT level, not on the task object itself.
--
-- Common error: "Insufficient privileges to execute task"
--               even when the user owns the task.
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS pipeline_role;
GRANT ROLE pipeline_role TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE pipeline_role;

CREATE DATABASE IF NOT EXISTS executor_demo;
CREATE SCHEMA IF NOT EXISTS executor_demo.tpch;
GRANT USAGE ON DATABASE executor_demo TO ROLE pipeline_role;
GRANT ALL ON SCHEMA executor_demo.tpch TO ROLE pipeline_role;
GRANT USAGE ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE pipeline_role;
GRANT USAGE ON SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 TO ROLE pipeline_role;
GRANT SELECT ON TABLE SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS TO ROLE pipeline_role;

USE ROLE pipeline_role;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE TABLE executor_demo.tpch.order_stats (
  run_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  total_orders NUMBER,
  avg_price FLOAT
);

CREATE OR REPLACE TASK executor_demo.tpch.daily_order_stats
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
INSERT INTO executor_demo.tpch.order_stats (total_orders, avg_price)
SELECT COUNT(*), AVG(o_totalprice)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- === CONTRAST: try to resume without EXECUTE TASK ===
ALTER TASK executor_demo.tpch.daily_order_stats RESUME;
-- Expected: SQL execution error: Cannot execute task,
--           EXECUTE TASK privilege must be granted to owner role

-- === DEMONSTRATE: grant EXECUTE TASK, then resume ===
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE pipeline_role;

USE ROLE pipeline_role;
ALTER TASK executor_demo.tpch.daily_order_stats RESUME;
-- Expected: Statement executed successfully

-- Verify it is running
SHOW TASKS LIKE 'daily_order_stats' IN SCHEMA executor_demo.tpch;

-- === CLEANUP ===
USE ROLE pipeline_role;
ALTER TASK executor_demo.tpch.daily_order_stats SUSPEND;

USE ROLE ACCOUNTADMIN;
DROP TASK IF EXISTS executor_demo.tpch.daily_order_stats;
DROP TABLE IF EXISTS executor_demo.tpch.order_stats;
REVOKE EXECUTE TASK ON ACCOUNT FROM ROLE pipeline_role;
DROP ROLE IF EXISTS pipeline_role;
DROP DATABASE IF EXISTS executor_demo;

-- ============================================================
-- Cleanup (run after you're done with this example)
-- ============================================================
-- See .cortex/skills/executor-role-workshop/cleanup/SKILL.md
-- or run: $executor-role-workshop cleanup
-- ============================================================
