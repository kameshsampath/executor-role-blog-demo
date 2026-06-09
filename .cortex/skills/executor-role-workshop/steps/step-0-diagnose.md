---
name: executor-role-workshop-diagnose
description: Diagnose executor role problems — triage symptom to root cause
---

# Step 0: Diagnose Your Executor Role Problem

## Triage

Use `ask_user_question` with these 3 questions simultaneously:

**Question 1:**
- Header: "Object type"
- Question: "What type of Snowflake object is involved?"
- Options: ["Stored procedure", "Task", "Dynamic table", "Masking/row access policy", "View", "UDF / UDTF", "Alert"]

**Question 2:**
- Header: "Symptom"
- Question: "What is the symptom or error?"
- Options:
  - "Insufficient privileges — but the role has the grant"
  - "Task won't resume or stays suspended"
  - "Task is in started state but body never executes"
  - "Dynamic table refresh fails with permissions error"
  - "Masking policy not applying the right role"
  - "Object behaves differently through a view"
  - "Other / I'll describe it"

**Question 3:**
- Header: "EXECUTE AS"
- Question: "Do you know the EXECUTE AS mode or owner role? (If unsure, pick 'Not sure')"
- Options: ["EXECUTE AS OWNER (default)", "EXECUTE AS CALLER", "Not sure", "N/A — not a stored proc"]

## Diagnosis routing

Based on answers, route to the matching step:

| Object | Symptom | Route |
|--------|---------|-------|
| Stored procedure | Insufficient privileges | `owners-rights.md` (Owner's Rights) |
| Stored procedure | EXECUTE AS CALLER and can't access owner's objects | `owners-rights.md` (Owner's Rights) |
| Task | Won't resume / stays suspended | `execute-task.md` (Execute Task) |
| Task | Started state but body never executes | `execute-task.md` — note: missing `EXECUTE TASK ON ACCOUNT` for scheduler |
| Dynamic table | Refresh fails with permissions | `dynamic-table.md` (Dynamic Table) |
| Masking / row access policy | Wrong role returned | Ask follow-up: "Does your policy use `INVOKER_ROLE()` or `CURRENT_ROLE()`?" → `INVOKER_ROLE()` → `masking-invoker.md`; `CURRENT_ROLE()` → `masking-current-role.md`; Not sure → `masking-invoker.md` (the more common trap) |
| Alert | Won't fire / insufficient privileges | `execute-task.md` — note: alerts follow the same `EXECUTE ALERT ON ACCOUNT` pattern as tasks |
| View | Behaves differently through view | `mental-model.md` (Mental Model) — start here |
| Unsure | Any | `mental-model.md` (Mental Model) — start here |

Before routing, briefly explain the diagnosis:
> "Based on your answers: this looks like a **[gap description]** problem.
> The executor role here is **[role]** because **[reason]**.
> Let's walk through it."

Then load the matched step file.
