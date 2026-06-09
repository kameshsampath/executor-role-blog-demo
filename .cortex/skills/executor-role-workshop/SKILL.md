---
name: executor-role-workshop
description: >
  Interactive diagnostic workshop for Snowflake's executor role model.
  Load when users ask about: stored procedure insufficient privileges,
  "I have the privilege but it still fails", EXECUTE AS OWNER vs CALLER,
  INVOKER_ROLE vs CURRENT_ROLE inside objects, task won't resume,
  EXECUTE TASK grant, dynamic table owner context, masking policy
  returning wrong role, executor role concept, who is running this query.
  Trigger phrases: "executor role", "EXECUTE AS", "INVOKER_ROLE",
  "stored procedure permission", "task won't resume", "masking policy context".
---

# Executor Role Workshop Skill

## Global Rules

1. **Three mandatory presentation points per step** -- Present these sections verbatim:
   - "Why this matters" -- the teaching moment
   - "What we'll do" -- preview of actions
   - "What we did" -- summary of completed work
   Never skip, summarize, or paraphrase any of the three.

2. **Plan mode gate** -- Call `enter_plan_mode` immediately after marking a step IN_PROGRESS.
   Present "Why this matters" + "What we'll do" inside plan mode.
   Call `exit_plan_mode` with a summary after the dry-run / preview. This is the single
   confirmation gate. There are no intermediate `Proceed?` asks within the step flow.

3. **SQL execution** -- Before running any SQL:
   - Run `cortex connections list` to check for an active Snowflake connection
   - If connected: run SQL via `sql_execute` tool
   - If not connected: show SQL blocks for manual copy-paste with a note:
     "No active connection detected -- copy and run this SQL in your Snowflake worksheet."

4. **Always use markdown** for all user-facing output (tables, code blocks, admonitions)

5. **Never hallucinate** -- if uncertain about a value, use `ask_user_question` to confirm

6. **SNOWFLAKE_SAMPLE_DATA** -- All SQL demos use `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1`.
   This database is available in every Snowflake account -- no data loading required.

7. **Beats** -- Every step must present a Reflect prompt and a pre-execution SQL preview (fail vs pass) inside plan mode, before the user confirms execution. The Reflect prompt asks the learner to predict what will happen. The pre-execution preview shows labeled SQL blocks: one marked `-- Will fail:` with the expected error, one marked `-- Will pass:` with the expected output. Never run SQL without showing this contrast first. The Reflect and pre-exec preview appear between "What we'll do" and the `exit_plan_mode` call.

8. **Resource prefix** -- All SQL demos use `$DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop'`. Each SQL block sets it automatically at the top. No manual action needed.

9. **Inter-step navigation** -- At the end of every step, before marking it complete, show a one-line "Up next" hint:
   ```
   Up next → $executor-role-workshop <next-concept>   |   or jump → $executor-role-workshop troubleshoot
   ```
   Guided tour order: **setup → mental-model → owners-rights → execute-task → dynamic-table → masking-invoker → masking-current-role → troubleshoot**

## Routing

| Command | Route |
|---------|-------|
| `$executor-role-workshop` (no args) | Intro -> full tour (setup -> mental-model) |
| `$executor-role-workshop diagnose` | `steps/step-0-diagnose.md` |
| `$executor-role-workshop setup` | `steps/setup.md` |
| `$executor-role-workshop mental-model` | `steps/mental-model.md` |
| `$executor-role-workshop owners-rights` | `steps/owners-rights.md` |
| `$executor-role-workshop execute-task` | `steps/execute-task.md` |
| `$executor-role-workshop dynamic-table` | `steps/dynamic-table.md` |
| `$executor-role-workshop masking-invoker` | `steps/masking-invoker.md` |
| `$executor-role-workshop masking-current-role` | `steps/masking-current-role.md` |
| `$executor-role-workshop troubleshoot` | `steps/troubleshoot.md` |
| `$executor-role-workshop cleanup` | `cleanup/SKILL.md` |

## Introduction (no-args entry)

When `$executor-role-workshop` is invoked with no arguments:

1. Call `enter_plan_mode`
2. Present this overview:

────────────────────────────────────────

   > **Executor Role Workshop**
   >
   > In Snowflake, the role that *calls* an object is not the role that *runs* it.
   > That distinction -- the executor role -- explains a whole class of permission errors.
   >
   > | Concept | Object |
   > |---------|--------|
   > | Setup | SET DEMO_PREFIX session variable, create shared objects |
   > | Mental Model | `CURRENT_ROLE()` vs `INVOKER_ROLE()` |
   > | Owner's Rights | Stored procedure `EXECUTE AS OWNER` |
   > | Execute Task | `EXECUTE TASK` at account level |
   > | Dynamic Table | `EXECUTE AS USER` identity pinning |
   > | Masking: INVOKER_ROLE() | `INVOKER_ROLE()` in masking policies |
   > | Masking: CURRENT_ROLE() | `CURRENT_ROLE()` and caller's rights |
   > | Troubleshoot | Symptom -> root cause -> fix |

────────────────────────────────────────

3. Call `exit_plan_mode` with a one-line summary
4. Go directly to `steps/setup.md` to begin the tour. Do NOT ask a question first.
5. At the end of setup, add this note:
   > To diagnose a specific problem instead, run: `$executor-role-workshop diagnose`.
   > To jump to a concept, run: `$executor-role-workshop <concept-name>`.
