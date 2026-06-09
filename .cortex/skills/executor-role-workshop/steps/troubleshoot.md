---
name: executor-role-workshop-troubleshoot
description: Troubleshooting - symptom to root cause to fix
---

## Mark IN_PROGRESS

```bash
cortex ctx step start troubleshoot
```

> Call enter_plan_mode before presenting.

# Troubleshooting: Symptom to Root Cause to Fix

## Why this matters

When you hit an executor role error in production, you need a fast path from symptom to root
cause to fix. The troubleshooting table below is that path.

Each row is a real error or symptom you have seen or will see. Knowing the cause and fix in
advance means spending minutes on the fix, not hours on the investigation.

After this step you have the complete executor role model: mental model, all object types,
the decision matrix, and the troubleshooting table.

## What we'll do

1. Present the full troubleshooting table (Symptom -> Cause -> Fix)
2. Run a diagnostic query to inspect `EXECUTE AS` mode of all procedures in a schema
3. Summarize the complete executor role model

## Troubleshooting Table

| Error or Symptom | Cause | Fix |
|------------------|-------|-----|
| `Cannot execute task, EXECUTE TASK privilege must be granted to owner role` | `EXECUTE TASK` is account-level; OWNERSHIP does not imply it | `GRANT EXECUTE TASK ON ACCOUNT TO ROLE <owner_role>` |
| Dynamic table refreshes fail after `GRANT OWNERSHIP` | New owner role lacks SELECT on sources or USAGE on warehouse | Grant privileges to new role before transfer; `ALTER DYNAMIC TABLE ... RESUME` |
| `User stage file access is not allowed within an owner's rights SP or UDF` | Owner-context objects cannot access user stages | Use named internal stages; pass paths via `BUILD_SCOPED_FILE_URL()` |
| Masking policy unmasks data through a view despite unprivileged session role | `INVOKER_ROLE()` evaluates the view owner, not the session role | Switch to `CURRENT_ROLE()` for session-role-based enforcement |
| Owner's rights proc fails: `SQL variable ... is not defined` | Owner mode cannot read caller's session variables | Pass the variable as an explicit proc parameter |
| Nested proc unexpectedly runs as owner's rights | Entire chain inherits owner's rights once any proc in it is owner's rights | Extract logic into standalone procs; restructure so owner's rights proc does not call caller's rights procs |
| `Insufficient privileges to execute ALERT` | `EXECUTE ALERT` is account-level; OWNERSHIP does not imply it | `GRANT EXECUTE ALERT ON ACCOUNT TO ROLE <owner_role>` |

## Decision Matrix Quick Reference

| Goal | Use | Notes |
|------|-----|-------|
| Let a low-privilege role call a proc doing privileged work | `EXECUTE AS OWNER` | Caller needs only `USAGE` on the proc; owner's grants do the rest |
| Proc must read the caller's session variables or current db | `EXECUTE AS CALLER` | Owner mode is isolated from caller session state |
| Native App proc needs consumer account object access | `EXECUTE AS RESTRICTED CALLER` | Consumer uses `GRANT CALLER` to explicitly authorize access |
| Dynamic table refresh needs `CURRENT_USER()` in policy | `EXECUTE AS USER <name>` | Default SYSTEM user fails policy conditions that check user identity |
| Masking policy based on who runs the query | `CURRENT_ROLE()` in policy | Evaluates session role regardless of object ownership |
| Masking policy based on who owns the executing object | `INVOKER_ROLE()` in policy | Evaluates view owner, proc owner, task owner, not session role |

### Reflect

Before reading the troubleshooting table: pick one error you have seen or expect to see. What do you think the root cause is? After reading the table, see if the explanation matches your thinking.

### What to expect

No fail/pass SQL in this step. The diagnostic query always succeeds:

```sql
-- List procedures in the demo schema
SHOW PROCEDURES IN SCHEMA <your_prefix>.tpch;
-- Expected: show_context, high_value_orders listed

-- Inspect execute_as for each
USE DATABASE <your_prefix>;
USE SCHEMA tpch;
DESCRIBE PROCEDURE show_context();
-- Expected: execute as = OWNER

DESCRIBE PROCEDURE high_value_orders(FLOAT);
-- Expected: execute as = OWNER
```

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL block below with a note:
"No active connection detected -- copy and run this SQL in your Snowflake worksheet."

### Diagnostic query: inspect EXECUTE AS mode for all procedures

```sql
-- Variable block: pre-declare all names used in this step
SET DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_DB     = $DEMO_PREFIX;
SET DEMO_SCHEMA = $DEMO_PREFIX || '.tpch';

-- List all user-defined procedures in the demo schema
-- (information_schema.procedures follows SQL standard, no execute_as column)
SHOW PROCEDURES IN SCHEMA IDENTIFIER($DEMO_SCHEMA);

-- Inspect execute_as mode for each procedure individually using DESCRIBE PROCEDURE
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA tpch;
DESCRIBE PROCEDURE show_context();
DESCRIBE PROCEDURE high_value_orders(FLOAT);
```

`DESCRIBE PROCEDURE` returns a property table including `execute as`:
- `OWNER` -- runs as the procedure owner's role (owner's rights)
- `CALLER` -- runs as the calling user's role (caller's rights)
- `RESTRICTED CALLER` -- Native Apps only

## What we did

You now have the complete executor role model:

- **Mental model**: `CURRENT_ROLE()` = session identity; `INVOKER_ROLE()` = executor identity
- **Stored procedures**: `EXECUTE AS OWNER` (privilege delegation) vs `EXECUTE AS CALLER` (session access)
- **Tasks**: `EXECUTE TASK ON ACCOUNT` is separate from OWNERSHIP
- **Dynamic tables**: `EXECUTE AS USER` pins a named identity for user-context policies
- **Masking policies**: `INVOKER_ROLE()` for object-ownership enforcement; `CURRENT_ROLE()` for session enforcement
- **Troubleshooting**: symptom -> root cause -> fix for every common executor role error

The executor role is not a feature. It is a model. Once you have the model, the errors explain themselves.

### Recap

Key insight: every executor role problem has a known root cause. The troubleshooting table maps each symptom to the cause and the fix.

- OWNERSHIP is not the same as EXECUTE permission. This applies to tasks, alerts, and other objects with account-level execution privileges.
- INVOKER_ROLE() and CURRENT_ROLE() are not interchangeable in masking policies. The difference surfaces when queries pass through views or owner's rights procedures.
- Owner's rights procedures cannot read caller session variables. Pass values as parameters instead.

## Mark COMPLETE

```bash
cortex ctx step done troubleshoot
```

## Cleanup

Use `ask_user_question`:
- Header: "Cleanup"
- Question: "Run cleanup to remove all demo objects?"
- Options: ["Yes, clean up", "No, keep objects", "Show me the cleanup SQL first"]

If "Yes": route to `cleanup/SKILL.md`

If "Show me the cleanup SQL first": show this SQL block, then ask again to confirm:

```sql
USE ROLE ACCOUNTADMIN;

-- Variable block
SET DEMO_PREFIX    = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_DB        = $DEMO_PREFIX;
SET R_DATA_ENG     = $DEMO_PREFIX || '_data_eng';
SET R_ANALYST      = $DEMO_PREFIX || '_analyst';
SET R_VIEW_CREATOR = $DEMO_PREFIX || '_view_creator';
SET R_PIPELINE     = $DEMO_PREFIX || '_pipeline';
SET R_TRANSFORM    = $DEMO_PREFIX || '_transform';
SET SVC_USER       = $DEMO_PREFIX || '_svc';

-- Revoke account-level privileges before dropping roles
REVOKE EXECUTE TASK ON ACCOUNT FROM ROLE IDENTIFIER($R_PIPELINE);

-- Drop the demo database (cascades to all schemas, tables, views, procs, tasks, policies)
DROP DATABASE IF EXISTS IDENTIFIER($DEMO_DB);

-- Drop demo roles
DROP ROLE IF EXISTS IDENTIFIER($R_DATA_ENG);
DROP ROLE IF EXISTS IDENTIFIER($R_ANALYST);
DROP ROLE IF EXISTS IDENTIFIER($R_VIEW_CREATOR);
DROP ROLE IF EXISTS IDENTIFIER($R_PIPELINE);
DROP ROLE IF EXISTS IDENTIFIER($R_TRANSFORM);

-- Drop service user (created in dynamic-table step)
SET g = 'DROP USER IF EXISTS ' || $SVC_USER; EXECUTE IMMEDIATE $g;
```

If "No, keep objects": stop. Do not execute.
