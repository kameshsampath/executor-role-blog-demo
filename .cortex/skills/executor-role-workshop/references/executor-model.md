---
name: executor-role-workshop-executor-model
description: Reference — executor role mental model, object table, and decision matrix
---

# Reference: Executor Role Mental Model

## The Two Core Functions

When Snowflake runs a stored procedure, task, UDF, or dynamic table, it evaluates
privileges against a specific role. That role is the **executor role**: whose grants
are checked, not necessarily the role of the person who triggered execution.

Two context functions expose this at query time:

| Function | Returns | When they differ |
|----------|---------|------------------|
| `CURRENT_ROLE()` | The session role of the user running the query | Always returns session role |
| `INVOKER_ROLE()` | The role Snowflake uses for the currently executing object | NULL at top level; diverges inside objects |
| `CURRENT_USER()` | The session user (not the role) | Can differ from executor user in dynamic tables |

At the top-level session, `CURRENT_ROLE()` and `INVOKER_ROLE()` return the same value.
Inside a stored procedure, view, task, or masking policy, they diverge.

**The divergence is intentional.** It is the entire point of the executor role model.

## Full Object-Type Table

| Object | Default Executor | Configurable? | Syntax | Extra Privilege Required |
|--------|-----------------|---------------|--------|-------------------------|
| **Stored Procedure** | Owner role | Yes | `EXECUTE AS OWNER \| CALLER \| RESTRICTED CALLER` | `USAGE` on proc |
| **Task** | Owner role | No | — | `EXECUTE TASK` (account-level) |
| **Dynamic Table** | Owner role as SYSTEM user | Yes (user) | `EXECUTE AS USER <name>` | `IMPERSONATE` on target user |
| **UDF / UDTF** | Owner role | No | — | `USAGE` on function |
| **Alert** | Owner role | No | — | `EXECUTE ALERT` (account-level) |
| **Streamlit App** | Owner role | No | — | Owner must have data privileges |
| **Masking / Row Policy** | Context-dependent | Via policy body | `INVOKER_ROLE()` or `CURRENT_ROLE()` | Enterprise Edition |

> Dynamic tables run as an internal SYSTEM user by default.
> The owner role's grants apply, but `CURRENT_USER()` returns a system identity, not a
> named user. Use `EXECUTE AS USER` when policies or audit trails require a real user.

## EXECUTE AS Decision Matrix

| Goal | Use | Notes |
|------|-----|-------|
| Let a low-privilege role call a proc doing privileged work | `EXECUTE AS OWNER` | Caller needs only `USAGE` on the proc; owner's grants do the rest |
| Proc must read the caller's session variables or current db | `EXECUTE AS CALLER` | Owner mode is isolated from caller session state |
| Native App proc needs consumer account object access | `EXECUTE AS RESTRICTED CALLER` | Consumer uses `GRANT CALLER` to explicitly authorize access |
| Dynamic table refresh needs `CURRENT_USER()` in policy | `EXECUTE AS USER <name>` | Default SYSTEM user fails policy conditions that check user identity |
| Masking policy based on who runs the query | `CURRENT_ROLE()` in policy | Evaluates session role regardless of object ownership |
| Masking policy based on who owns the executing object | `INVOKER_ROLE()` in policy | Evaluates view owner, proc owner, task owner, not session role |

Key behavioral differences between owner's rights and caller's rights:

| Behavior | Owner's Rights | Caller's Rights |
|----------|---------------|----------------|
| Privileges used | Owner role | Caller's current role |
| Session variables | Cannot read or set | Can read and set |
| Database/schema context | Proc's own db/schema | Caller's current db/schema |
| Source code visibility | Hidden from non-owners | Visible to callers |
| Nested procs | Entire chain runs as owner's rights | Only if full chain is caller's rights |

> Once an owner's rights procedure is anywhere in a nested call chain, every procedure
> called from it also runs as owner's rights, even those individually set to `EXECUTE AS CALLER`.

## Diagnostic Question Order

When debugging an executor role error, work through these questions in order:

1. **What object type is this?**
   - Determines the default executor (almost always owner role)
   - Exceptions: dynamic tables use SYSTEM user; masking policies depend on context

2. **What `EXECUTE AS` mode is it in?**
   - For stored procedures: check `execute_as` in `information_schema.procedures`
   - For dynamic tables: check if `EXECUTE AS USER` is set
   - For tasks/alerts: always owner; but `EXECUTE TASK` / `EXECUTE ALERT` is account-level

3. **What privilege does the executor role lack?**
   - The executor role is determined by steps 1–2
   - The missing grant is on *that* role, not the calling session role
   - Common gap: account-level privileges (`EXECUTE TASK`, `EXECUTE ALERT`) not implied by ownership

```sql
-- Quick diagnostic: what EXECUTE AS mode are my procedures in?
SELECT 
    procedure_name,
    argument_signature,
    procedure_language,
    execute_as
FROM information_schema.procedures
WHERE procedure_schema = 'PUBLIC'
ORDER BY procedure_name;
```

## Context Functions in Masking Policy Bodies

| Context | `INVOKER_ROLE()` returns | `CURRENT_ROLE()` returns |
|---------|--------------------------|-------------------------|
| Direct table query | Session role | Session role |
| View query | View owner role | Session role |
| Owner's rights stored proc | Proc owner role | Session role |
| Caller's rights stored proc | Session role | Session role |
| Task | Task owner role | Session role |
| UDF | UDF owner role | Session role |
