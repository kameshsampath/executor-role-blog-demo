---
name: executor-role-workshop-mental-model
description: Mental model - CURRENT_ROLE vs INVOKER_ROLE
---

## Mark IN_PROGRESS

```bash
cortex ctx step start mental-model
```

> Call enter_plan_mode before presenting.

# Mental Model: Who Is Actually Running This?

## Why this matters

When you call a stored procedure, you are not the one running it. The procedure's owner is.

In Snowflake, every object has two identity questions:

- **Who called it?** -> `CURRENT_ROLE()` -- the role in your session right now
- **Who is running it?** -> `INVOKER_ROLE()` -- the role Snowflake uses to evaluate privileges for this specific object

At the top-level session, they are the same. Inside a stored procedure, view, task, or masking policy, they can diverge completely. That divergence is intentional -- it is the entire point of the executor role model.

Here is the map across all Snowflake objects:

| Object | Default Executor | Configurable? |
|--------|-----------------|---------------|
| Stored Procedure | Owner role | Yes -- `EXECUTE AS` clause |
| Task | Owner role | No |
| Dynamic Table | Owner role (as SYSTEM user) | Yes -- `EXECUTE AS USER` |
| UDF / UDTF | Owner role | No |
| Alert | Owner role | No |
| Streamlit App | Owner role | No |
| Masking / Row Policy | Context-dependent | Via `INVOKER_ROLE()` or `CURRENT_ROLE()` in body |

Most objects default to the owner. Most surprises come from not knowing what "owner" means in each context.

### Theorem

> Inside a stored procedure that runs with `EXECUTE AS OWNER`, `CURRENT_ROLE()` returns the owner's role, not the caller's. The session switches to the owner's context when the procedure runs.

## What we'll do

Run a short SQL proof inside a stored procedure to show that inside an `EXECUTE AS OWNER` procedure, `CURRENT_ROLE()` returns the owner's role, not the caller's.

### Reflect

You are about to call a stored procedure created and owned by the `data_eng` role. Your session role is `analyst`. Inside the procedure, what does `CURRENT_ROLE()` return -- your session role (`analyst`) or the procedure owner's role (`data_eng`)? Make a prediction, then run the SQL.

### What to expect

No failure path in this step. All SQL succeeds. Watch the output values:

```sql
-- Before the call (you are analyst):
SELECT CURRENT_ROLE() AS caller_role_before_call;
-- Expected: <your_prefix>_analyst

-- Inside the procedure (owned by data_eng, EXECUTE AS OWNER):
CALL <your_prefix>.tpch.show_context();
-- Expected: role_inside_procedure = <your_prefix>_data_eng

-- The caller was _analyst. The executor was _data_eng. They differ.
-- That switch is the executor role model.
```

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL blocks below and skip execution.

### SQL demo

```sql
-- Set prefix (auto-set by setup, included here as fallback)
SET DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop';
USE WAREHOUSE COMPUTE_WH;

-- Step 1: note your current session role (this is the caller)
SELECT CURRENT_ROLE() AS your_session_role;

-- Step 2: create the proof procedure as data_eng (this role becomes the executor/owner)
-- Workshop note: in production, a different user would own data_eng and create this proc.
-- The caller (analyst) would never need data_eng. Here you play both roles with one account.
SET r = 'USE ROLE ' || $DEMO_PREFIX || '_data_eng'; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE IDENTIFIER($DEMO_PREFIX);
USE SCHEMA tpch;

CREATE OR REPLACE PROCEDURE show_context()
  RETURNS OBJECT
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
BEGIN
  RETURN OBJECT_CONSTRUCT(
    'role_inside_procedure', CURRENT_ROLE()
  );
END;

-- Step 3: grant call right to analyst
USE ROLE ACCOUNTADMIN;
SET g = 'GRANT USAGE ON PROCEDURE ' || $DEMO_PREFIX || '.tpch.show_context() TO ROLE ' || $DEMO_PREFIX || '_analyst'; EXECUTE IMMEDIATE $g;

-- Step 4: call as analyst -- observe the role switch
SET r = 'USE ROLE ' || $DEMO_PREFIX || '_analyst'; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;
SELECT CURRENT_ROLE() AS caller_role_before_call;
SET c = 'CALL ' || $DEMO_PREFIX || '.tpch.show_context()'; EXECUTE IMMEDIATE $c;
-- role_inside_procedure = _data_eng  (the owner/executor)
-- caller_role_before_call = _analyst (the caller)
-- They are different. That is the executor role model.
```

After running, explain what the output shows:
> `caller_role_before_call` returned the analyst role.
> `role_inside_procedure` returned the data_eng role.
> The procedure ran as its owner, not as you. That is the executor role in action.

## What we did

- Established that `CURRENT_ROLE()` is your session identity
- Created a procedure owned by data_eng with `EXECUTE AS OWNER`
- Called it as analyst
- Proved that inside the procedure, `CURRENT_ROLE()` returns data_eng's role, not analyst's
- Mapped all Snowflake object types to their default executor

### Recap

Key insight: `CURRENT_ROLE()` inside an `EXECUTE AS OWNER` procedure returns the owner's role, not the caller's role. The execution context switched.

- Before the call: `CURRENT_ROLE()` = analyst (the caller's session)
- Inside the procedure: `CURRENT_ROLE()` = data_eng (the owner/executor)
- This switch is the executor role model. The procedure ran as its owner, not as you.

## Mark COMPLETE

```bash
cortex ctx step done mental-model
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Owner's Rights?"
- Options: ["Yes, continue to Owner's Rights", "Jump to a specific concept", "Stop here"]
- If yes: load steps/owners-rights.md
