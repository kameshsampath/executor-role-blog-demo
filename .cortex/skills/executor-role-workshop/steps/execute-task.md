---
name: executor-role-workshop-execute-task
description: Tasks - EXECUTE TASK is account-level, OWNERSHIP is not enough
---

## Mark IN_PROGRESS

```bash
cortex ctx step start execute-task
```

> Call enter_plan_mode before presenting.

# Tasks: The Privilege That Ownership Does Not Grant

## Why this matters

Here is a bug that trips up everyone at least once.

You create a task. You own it. You grant your role `EXECUTE TASK ON ACCOUNT`. The task runs. You think you understand the privilege model.

Then someone removes `EXECUTE TASK ON ACCOUNT` from the owner role. The task is still in `started` state. It still looks healthy. But it silently stops executing on schedule.

The separation is deliberate. Snowflake splits task control into two distinct things:

- **State control** (`ALTER TASK RESUME/SUSPEND`): who can start and stop the task. Requires `OWNERSHIP` or `OPERATE` on the task object.
- **Execution permission** (`EXECUTE TASK ON ACCOUNT`): whether the Snowflake scheduler is allowed to actually fire the task. Account-level. Not implied by ownership.

A role can own a task, have full `OWNERSHIP`, and successfully resume it -- but without `EXECUTE TASK ON ACCOUNT`, the scheduler will not run the task body when the schedule triggers.

> Ownership means you control the object. EXECUTE TASK means you are allowed to fire it.
> Snowflake separates those deliberately.

### Theorem

> `EXECUTE TASK ON ACCOUNT` is an account-level privilege separate from task ownership. A role can own a task, change its state, and still have the scheduler refuse to execute it without this privilege.

## What we'll do

1. Create `pipeline_role` and grant it task and data access
2. Create a daily stats task owned by `pipeline_role`
3. Resume the task -- with OWNERSHIP, the state change succeeds
4. Grant `EXECUTE TASK ON ACCOUNT` to `pipeline_role` and confirm it is the execution gate
5. Suspend and clean up

### Reflect

A role owns a task and can successfully run `ALTER TASK ... RESUME`. Does that mean the task will execute on schedule? Ownership controls state. Something else controls execution. What is it?

### What to expect

```sql
-- Succeeds: the owner role can change task state (OWNERSHIP implies OPERATE)
ALTER TASK <your_prefix>.tpch.daily_order_stats RESUME;
-- Expected: Statement executed successfully
-- The task state is now "started" -- but it will not run on schedule yet

-- Without EXECUTE TASK ON ACCOUNT the scheduler refuses to fire the task body
-- Grant it to open the execution gate:
GRANT EXECUTE TASK ON ACCOUNT TO ROLE <your_prefix>_pipeline;
-- Now the task will actually execute when the CRON schedule triggers
```

> The key distinction: state control (OPERATE/OWNERSHIP) and execution permission (EXECUTE TASK) are separate.
> A task can be in `started` state and still never run without `EXECUTE TASK ON ACCOUNT`.

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL blocks below with a note:
"No active connection detected -- copy and run this SQL in your Snowflake worksheet."

### SQL demo

```sql
-- Variable block: pre-declare all names used in this step
SET DEMO_PREFIX  = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_DB      = $DEMO_PREFIX;
SET DEMO_SCHEMA  = $DEMO_PREFIX || '.tpch';
SET R_PIPELINE   = $DEMO_PREFIX || '_pipeline';
SET T_DAILY_STATS = $DEMO_PREFIX || '.tpch.daily_order_stats';
SET T_ORDER_STATS = $DEMO_PREFIX || '.tpch.order_stats';

-- ============================================================
-- Tasks Demo: EXECUTE TASK is Account-Level
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS IDENTIFIER($R_PIPELINE);
SET g = 'GRANT ROLE ' || $R_PIPELINE || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_PIPELINE);

GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB)   TO ROLE IDENTIFIER($R_PIPELINE);
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_PIPELINE);
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_PIPELINE; EXECUTE IMMEDIATE $g;

SET r = 'USE ROLE ' || $R_PIPELINE; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA tpch;

CREATE OR REPLACE TABLE order_stats (
  run_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  total_orders NUMBER,
  avg_price FLOAT
);

CREATE OR REPLACE TASK daily_order_stats
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
INSERT INTO order_stats (total_orders, avg_price)
SELECT COUNT(*), AVG(o_totalprice)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- === CONTRAST: try to resume without EXECUTE TASK ===
ALTER TASK IDENTIFIER($T_DAILY_STATS) RESUME;
-- Expected: SQL execution error: Cannot execute task,
--           EXECUTE TASK privilege must be granted to owner role

-- === DEMONSTRATE: grant EXECUTE TASK, then resume ===
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE IDENTIFIER($R_PIPELINE);

SET r = 'USE ROLE ' || $R_PIPELINE; EXECUTE IMMEDIATE $r;
ALTER TASK IDENTIFIER($T_DAILY_STATS) RESUME;
-- Expected: Statement executed successfully

-- Verify it is running
SHOW TASKS LIKE 'daily_order_stats' IN SCHEMA IDENTIFIER($DEMO_SCHEMA);

-- === CLEANUP ===
SET r = 'USE ROLE ' || $R_PIPELINE; EXECUTE IMMEDIATE $r;
ALTER TASK IDENTIFIER($T_DAILY_STATS) SUSPEND;

USE ROLE ACCOUNTADMIN;
DROP TASK IF EXISTS IDENTIFIER($T_DAILY_STATS);
DROP TABLE IF EXISTS IDENTIFIER($T_ORDER_STATS);
REVOKE EXECUTE TASK ON ACCOUNT FROM ROLE IDENTIFIER($R_PIPELINE);
DROP ROLE IF EXISTS IDENTIFIER($R_PIPELINE);
```

After running, explain what the output shows:
> `ALTER TASK RESUME` succeeded because the pipeline role owns the task (OWNERSHIP implies OPERATE).
> The task state is `started` -- but the scheduler will not run it until `EXECUTE TASK ON ACCOUNT` is granted.
> `GRANT EXECUTE TASK ON ACCOUNT` opened the execution gate. The task can now fire on its schedule.
> State control and execution permission are two separate things in Snowflake's privilege model.

## What we did

- Created a task owned by `pipeline_role`
- Confirmed that OWNERSHIP allows ALTER TASK RESUME (state control)
- Confirmed that the task state is `started` -- but execution requires a separate account-level privilege
- Granted `EXECUTE TASK ON ACCOUNT` -- the execution gate, not implied by ownership
- Observed the two distinct layers: state control (object-level) and execution permission (account-level)

`EXECUTE TASK ON ACCOUNT` is what tells the scheduler it is allowed to run the task body. Ownership is not that privilege.

### Recap

Key insight: task state and task execution are controlled by different privileges.

- `OWNERSHIP` or `OPERATE` on the task: lets you change task state (`ALTER TASK RESUME/SUSPEND`).
- `EXECUTE TASK ON ACCOUNT`: lets the Snowflake scheduler actually run the task body on its schedule.
- A task can be in `started` state and silently never execute without `EXECUTE TASK ON ACCOUNT`.
- This separation lets administrators control which roles can trigger execution independently of who manages task definitions.

## Mark COMPLETE

```bash
cortex ctx step done execute-task
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Dynamic Table?"
- Options: ["Yes, continue to Dynamic Table", "Jump to a specific concept", "Stop here"]
- If yes: load steps/dynamic-table.md
