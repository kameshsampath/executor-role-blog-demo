---
name: executor-role-workshop-troubleshooting
description: Reference — full troubleshooting table for executor role errors
---

# Reference: Executor Role Troubleshooting

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
| `IDENTIFIER($var \|\| 'suffix')` raises invalid identifier | IDENTIFIER() requires a simple session variable reference, not an expression | Pre-declare: `SET R = $PREFIX \|\| '_suffix';` then `IDENTIFIER($R)` |
| `USE ROLE IDENTIFIER(...)` raises SQL syntax error | USE ROLE does not support IDENTIFIER() | `SET r = 'USE ROLE ' \|\| $ROLE; EXECUTE IMMEDIATE $r;` |
| `CREATE OR REPLACE MASKING POLICY` fails on an attached policy | Policy is referenced by a column — cannot replace while attached | `ALTER TABLE t MODIFY COLUMN c UNSET MASKING POLICY;` then replace, then re-apply |
| Masking policy raises type mismatch error despite correct logic | Policy argument type doesn't match column data type exactly (e.g. FLOAT vs NUMBER(12,2)) | Match exactly: `NUMBER(12,2)` column → `(val NUMBER) RETURNS NUMBER` |
| Task state is `started` but body never executes | OWNERSHIP/OPERATE allows `ALTER TASK RESUME` (state change) but not scheduler execution | `GRANT EXECUTE TASK ON ACCOUNT TO ROLE <owner_role>` |
| `SQL variable ... is not defined` inside `CREATE PROCEDURE` body | Session variable missing at compile time | `SET my_var = 'value';` before the `CREATE PROCEDURE` statement |
| Dynamic table body contains `EXECUTE IMMEDIATE $g` literally | Snowflake stores the DT definition verbatim; session variable is not expanded | Use scripting block: `EXECUTE IMMEDIATE $$ DECLARE ... BEGIN sql := '...'; EXECUTE IMMEDIATE sql; END; $$;` |
| `DESCRIBE PROCEDURE` needed to check execution mode | `information_schema.procedures` has no `execute_as` column | `DESCRIBE PROCEDURE proc_name(arg_type);` returns the execute as property |

## Context Functions Quick Reference

| Function | Returns | Notes |
|----------|---------|-------|
| `CURRENT_ROLE()` | Session role (always the role in your current session) | Constant throughout the query regardless of object nesting |
| `INVOKER_ROLE()` | Executor role for the currently executing object | NULL at top level; changes based on object type and EXECUTE AS mode |
| `CURRENT_USER()` | Session user | Dynamic tables default to SYSTEM user; use `EXECUTE AS USER` to pin a named user |

## Tips and Gotchas

- **Ownership transfer on dynamic tables requires a privilege pre-flight.** Grant the new
  owner role SELECT on all source tables and USAGE on the warehouse *before* transferring
  ownership. Transferring first causes the next scheduled refresh to fail and the table
  to auto-suspend.

- **`EXECUTE TASK` and `EXECUTE ALERT` are account-level.** Neither is implied by
  OWNERSHIP. A role can own a task or alert and still be blocked from running it.
  Grant both `EXECUTE TASK ON ACCOUNT` and `EXECUTE ALERT ON ACCOUNT` explicitly.

- **`INVOKER_ROLE()` on a view returns the view owner, not the session role.** If your
  masking policy uses `INVOKER_ROLE()` and is applied to a table accessed via a view,
  the function evaluates the view owner role. Use `CURRENT_ROLE()` if the intent is to
  enforce based on who is running the query.

- **Owner's rights procs hide source code from callers.** `GET_DDL()` on an owner's rights
  proc returns nothing for non-owners. This is intentional. Use it for IP protection.

- **Caller's rights requires the entire call chain.** A single owner's rights proc anywhere
  in a nested call hierarchy converts all downstream procs to owner's rights, regardless
  of their individual `EXECUTE AS` settings.

- **`IDENTIFIER()` only accepts simple session variable references, not expressions.**
  `IDENTIFIER($var || '_suffix')` fails everywhere. Pre-declare: `SET R = $PREFIX || '_suffix'; IDENTIFIER($R)`

- **`USE ROLE IDENTIFIER(...)` is not valid syntax.** Use `SET r = 'USE ROLE ' || $ROLE; EXECUTE IMMEDIATE $r;`

- **`GRANT IMPORTED PRIVILEGES ... TO ROLE IDENTIFIER(...)` requires EXECUTE IMMEDIATE.**

- **Masking policy argument type must match the column's declared type exactly.**
  `NUMBER(12,2)` → `(val NUMBER) RETURNS NUMBER`. FLOAT raises a compile error.

- **`CREATE OR REPLACE MASKING POLICY` fails while the policy is attached.**
  `UNSET MASKING POLICY` on the column first, then replace, then re-apply.

- **Session variables don't exist in Dynamic Table refresh context.**
  `EXECUTE AS USER IDENTIFIER($var)` fails at refresh time. Use a Scripting block with literal names.

- **`EXECUTE IMMEDIATE $g` stores command text verbatim as the DT body.**
  Use `EXECUTE IMMEDIATE $$ DECLARE ... BEGIN sql := '...'; EXECUTE IMMEDIATE sql; END; $$;`

- **Session variables in `CREATE PROCEDURE` DECLARE blocks must exist at compile time.**
  `SET my_var = 'x';` must precede the `CREATE PROCEDURE` statement.

- **`RETURNS TABLE` column types must match the SELECT output exactly.**
  Add explicit `::NUMBER`, `::FLOAT`, `::VARCHAR` casts.

- **`EXECUTE TASK` controls two distinct things.**
  OWNERSHIP/OPERATE → ALTER TASK state. `EXECUTE TASK ON ACCOUNT` → scheduler fires body.
  A task can show `started` and silently never execute without the account-level privilege.

- **`DESCRIBE PROCEDURE proc_name(arg_type)` reveals the `execute as` property.**
  `information_schema.procedures` has no `execute_as` column.

## Minimum Privilege Sets

### Role that owns and executes a task

```sql
GRANT EXECUTE TASK ON ACCOUNT TO ROLE task_runner_role;
GRANT OWNERSHIP ON TASK mydb.myschema.my_task TO ROLE task_runner_role;
GRANT USAGE ON WAREHOUSE task_wh TO ROLE task_runner_role;
```

### Role that owns and executes an alert

```sql
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE alert_owner_role;
GRANT OWNERSHIP ON ALERT mydb.myschema.my_alert TO ROLE alert_owner_role;
GRANT USAGE ON WAREHOUSE monitor_wh TO ROLE alert_owner_role;
```

### Role that uses EXECUTE AS USER on a dynamic table

```sql
GRANT IMPERSONATE ON USER svc_transform TO ROLE transform_role;
GRANT ROLE transform_role TO USER svc_transform;
-- Dynamic table owner role = transform_role
-- Executor user = svc_transform
```

## References

- [Caller's Rights and Owner's Rights Stored Procedures](https://docs.snowflake.com/en/developer-guide/stored-procedure/stored-procedures-rights)
- [Restricted Caller's Rights](https://docs.snowflake.com/en/developer-guide/restricted-callers-rights)
- [Dynamic Table Access Control](https://docs.snowflake.com/en/user-guide/dynamic-tables/privileges)
- [Dynamic Tables: EXECUTE AS USER](https://docs.snowflake.com/en/release-notes/2026/other/2026-02-18-dynamic-tables-execute-as-user)
- [INVOKER_ROLE Function](https://docs.snowflake.com/en/sql-reference/functions/invoker_role)
- [IS_GRANTED_TO_INVOKER_ROLE Function](https://docs.snowflake.com/en/sql-reference/functions/is_granted_to_invoker_role)
- [Advanced Column-Level Security Topics](https://docs.snowflake.com/en/user-guide/security-column-advanced)
- [Task Access Control](https://docs.snowflake.com/en/user-guide/tasks-intro)
