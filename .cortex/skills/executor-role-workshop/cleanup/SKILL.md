---
name: executor-role-workshop-cleanup
description: Remove all executor-role-workshop demo objects (roles, database, procedures)
---

# Cleanup: Remove Demo Objects

This removes all objects created by the executor role workshop steps.

All demo objects are prefixed with your Snowflake username. DEMO_PREFIX is set automatically at the top of each SQL block -- no manual action needed.

## Plan Mode: Show What Will Be Dropped

Call `enter_plan_mode` and present this table:

```
Object                                          | Command
------------------------------------------------|----------------------------------------------------------
DATABASE <prefix>_executor_role_workshop        | DROP DATABASE IF EXISTS IDENTIFIER($DEMO_PREFIX)
ROLE <prefix>_executor_role_data_eng            | EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_data_eng'
ROLE <prefix>_executor_role_analyst             | EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_analyst'
ROLE <prefix>_executor_role_view_creator        | EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_view_creator'
ROLE <prefix>_executor_role_pipeline            | EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_pipeline'
ROLE <prefix>_executor_role_transform           | EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_transform'
USER <prefix>_executor_role_svc                 | EXECUTE IMMEDIATE 'DROP USER IF EXISTS ' || $DEMO_PREFIX || '_svc'
```

Note: `<prefix>` is `LOWER(CURRENT_USER())`, for example `kameshs`.

Use `ask_user_question`:
- Header: "Cleanup"
- Question: "Drop all demo objects? This cannot be undone."
- Options: ["Yes, clean up", "Cancel"]

If cancel: stop. Do not execute.

If confirmed: call `exit_plan_mode`, then run `cortex connections list` to verify a connection
exists before executing. If no connection: show the SQL for manual execution.

```sql
USE ROLE ACCOUNTADMIN;

-- Set your prefix if not already set
SET DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop';

-- Revoke account-level privileges before dropping roles
EXECUTE IMMEDIATE 'REVOKE EXECUTE TASK ON ACCOUNT FROM ROLE ' || $DEMO_PREFIX || '_pipeline';

-- Drop the demo database (cascades to all schemas, tables, views, procs, tasks, policies)
DROP DATABASE IF EXISTS IDENTIFIER($DEMO_PREFIX);

-- Drop demo roles
EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_data_eng';
EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_analyst';
EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_view_creator';
EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_pipeline';
EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || $DEMO_PREFIX || '_transform';

-- Drop service user (created in dynamic-table step)
EXECUTE IMMEDIATE 'DROP USER IF EXISTS ' || $DEMO_PREFIX || '_svc';
```

## Confirmation

Show a summary after execution:

| Object | Status |
|--------|--------|
| <prefix>_executor_role database | dropped |
| <prefix>_executor_role_data_eng | dropped |
| <prefix>_executor_role_analyst | dropped |
| <prefix>_executor_role_view_creator | dropped |
| <prefix>_executor_role_pipeline | dropped |
| <prefix>_executor_role_transform | dropped |
| <prefix>_executor_role_svc user | dropped |

The workshop SQL examples remain available in `steps/` for re-running.

To re-run the workshop from the beginning (Mental Model):

```
$executor-role-workshop mental-model
```
