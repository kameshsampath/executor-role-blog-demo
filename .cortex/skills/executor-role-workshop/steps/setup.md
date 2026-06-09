---
name: executor-role-workshop-setup
description: Create shared demo objects - database, schema, roles, grants
---

## Mark IN_PROGRESS

```bash
cortex ctx step start setup
```

> Call enter_plan_mode before presenting.

# Setup: Create Demo Objects

## Why this matters

The SQL demos across all steps share a database and roles. Creating them once here avoids repeating setup in every step. All objects are prefixed with your Snowflake username so multiple users can run the workshop on the same account without collisions.

## What we'll do

1. Compute your demo prefix using `CURRENT_USER()`
2. Create the demo database and tpch schema
3. Create all demo roles: data_eng, analyst, view_creator, pipeline, transform
4. Grant `SNOWFLAKE_SAMPLE_DATA` access to each role that needs it
5. Grant `USAGE` on `COMPUTE_WH` to all roles
6. Show you what was created

### Reflect

Before running: what happens if two people run this workshop on the same account without a prefix? What problem does the prefix solve? Think about it, then run the SQL.

### What to expect

No fail/pass contrast here. This is pure setup. All statements should succeed.

If any `CREATE ROLE` or `CREATE DATABASE` fails, check that `ACCOUNTADMIN` is your active role.

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL blocks below with a note:
"No active connection detected -- copy and run this SQL in your Snowflake worksheet."

### SQL demo

```sql
-- ============================================================
-- Setup: Create shared demo objects
-- All objects are prefixed with your Snowflake username.
-- ============================================================

-- Variable block: pre-declare all names used in this step
-- IDENTIFIER() requires a simple variable -- no || inside IDENTIFIER()
SET DEMO_PREFIX    = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_DB        = $DEMO_PREFIX;
SET DEMO_SCHEMA    = $DEMO_PREFIX || '.tpch';
SET R_DATA_ENG     = $DEMO_PREFIX || '_data_eng';
SET R_ANALYST      = $DEMO_PREFIX || '_analyst';
SET R_VIEW_CREATOR = $DEMO_PREFIX || '_view_creator';
SET R_PIPELINE     = $DEMO_PREFIX || '_pipeline';
SET R_TRANSFORM    = $DEMO_PREFIX || '_transform';
SELECT $DEMO_PREFIX AS your_demo_prefix;

USE ROLE ACCOUNTADMIN;

-- Create database and schema
CREATE DATABASE IF NOT EXISTS IDENTIFIER($DEMO_DB);
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($DEMO_SCHEMA);

-- Create demo roles
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_DATA_ENG);
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_ANALYST);
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_VIEW_CREATOR);
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_PIPELINE);
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_TRANSFORM);

-- Grant demo roles TO USER so you can switch to them with USE ROLE
-- (GRANT ROLE ... TO USER does not support IDENTIFIER() -- requires EXECUTE IMMEDIATE)
-- TO USER grants no privilege inheritance -- your default role is unaffected
--
-- Workshop note: in production, each role belongs to a different user or service account.
-- Here, one user (you) plays all roles. That is why all demo roles are granted to your user.
-- When you do USE ROLE data_eng to create a proc, then USE ROLE analyst to call it,
-- you need both roles assigned to your single user. A real analyst would only need analyst.
SET g = 'GRANT ROLE ' || $R_DATA_ENG     || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_ANALYST      || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_VIEW_CREATOR || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_PIPELINE     || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_TRANSFORM    || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_DATA_ENG);
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_ANALYST);
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_VIEW_CREATOR);
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_PIPELINE);
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($R_TRANSFORM);

-- Grant database usage
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB) TO ROLE IDENTIFIER($R_DATA_ENG);
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB) TO ROLE IDENTIFIER($R_ANALYST);
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB) TO ROLE IDENTIFIER($R_VIEW_CREATOR);
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB) TO ROLE IDENTIFIER($R_PIPELINE);
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB) TO ROLE IDENTIFIER($R_TRANSFORM);

-- Grant schema access
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_DATA_ENG);
GRANT USAGE ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_ANALYST);
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_VIEW_CREATOR);
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_PIPELINE);
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_TRANSFORM);

-- Grant SNOWFLAKE_SAMPLE_DATA access
-- (GRANT IMPORTED PRIVILEGES requires EXECUTE IMMEDIATE)
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_DATA_ENG;     EXECUTE IMMEDIATE $g;
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_VIEW_CREATOR; EXECUTE IMMEDIATE $g;
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_PIPELINE;     EXECUTE IMMEDIATE $g;
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_TRANSFORM;    EXECUTE IMMEDIATE $g;
```

After running, show the user:

> Your demo prefix is the value of `$DEMO_PREFIX`. All subsequent steps use this prefix for database, schema, and role names. The prefix is set as session variable `$DEMO_PREFIX`.

## What we did

- Set `$DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop'`
- Created database and tpch schema under that prefix
- Created 5 demo roles: data_eng, analyst, view_creator, pipeline, transform
- Granted warehouse and schema access to each role
- Granted `SNOWFLAKE_SAMPLE_DATA` access to roles that query it

### Recap

The prefix keeps objects isolated per user. Every step reuses these roles and this database. Setup runs once per session.

- All demo objects live under one database named for your username
- Each SQL block sets `$DEMO_PREFIX` automatically at the top -- no manual action needed.
- If you start a new session, re-run setup or set `$DEMO_PREFIX` manually at the top of your worksheet

## Mark COMPLETE

```bash
cortex ctx step done setup
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Ready to start with the mental model?"
- Options: ["Yes, start with Mental Model", "Jump to a specific concept"]

If yes: load `steps/mental-model.md`

If jump: ask which concept (Mental Model, Owner's Rights, Execute Task, Dynamic Table, Masking: INVOKER_ROLE(), Masking: CURRENT_ROLE(), Troubleshoot)

---

> To diagnose a specific problem instead, run: `$executor-role-workshop diagnose`.
> To jump to a concept, run: `$executor-role-workshop <concept-name>`.
