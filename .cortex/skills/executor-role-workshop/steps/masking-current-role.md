---
name: executor-role-workshop-masking-current-role
description: Masking policies - CURRENT_ROLE() for session-based enforcement; caller's rights context
---

## Mark IN_PROGRESS

```bash
cortex ctx step start masking-current-role
```

> Call enter_plan_mode before presenting.

# Masking: CURRENT_ROLE()

## Why this matters

The previous step showed the view trap: `INVOKER_ROLE()` evaluates the view owner when the table is
accessed through a view. The fix is `CURRENT_ROLE()`.

`CURRENT_ROLE()` inside a masking policy always returns the **session role** of the user running
the query -- regardless of how many views, procedures, or objects the query passes through.

The difference from `INVOKER_ROLE()` is precise:
- `INVOKER_ROLE()` = who owns the executing object (changes with nesting)
- `CURRENT_ROLE()` = who is running the session (constant throughout the query)

The context functions table for masking policies:

| Context | `INVOKER_ROLE()` returns | `CURRENT_ROLE()` returns |
|---------|--------------------------|-------------------------|
| Direct table query | Session role | Session role |
| View query | View owner role | Session role |
| Owner's rights stored proc | Proc owner role | Session role |
| Caller's rights stored proc | Session role | Session role |
| Task | Task owner role | Session role |
| UDF | UDF owner role | Session role |

For session-role-based enforcement, `CURRENT_ROLE()` is always correct.
`INVOKER_ROLE()` and `CURRENT_ROLE()` are not interchangeable.

### Theorem

> `CURRENT_ROLE()` inside a masking policy always returns the session role, regardless of how many views or procedures the query passes through.

## What we'll do

1. Continue from Masking: INVOKER_ROLE() setup (or re-create if starting fresh)
2. Replace the masking policy to use `CURRENT_ROLE()` instead of `INVOKER_ROLE()`
3. Query the same view as `analyst_role` -- prices now appear correctly
4. Show that `CURRENT_ROLE()` is stable across both direct and view access
5. Demonstrate a caller's rights stored procedure querying the masked column; masking evaluates the session role, not the proc owner

### Reflect

In the previous step, INVOKER_ROLE() broke through a view. Now the masking policy is switched to CURRENT_ROLE(). The analyst queries the same view. What changes? Will CURRENT_ROLE() give the same result as INVOKER_ROLE() through the view, or a different one?

### What to expect

```sql
-- Will pass (real prices): _analyst queries through the view, policy uses CURRENT_ROLE()
-- CURRENT_ROLE() = <your_prefix>_analyst -> policy condition matches -> real values
-- This is the same view that returned -1 in the previous step with INVOKER_ROLE()

-- The only change: the policy body now uses CURRENT_ROLE() instead of INVOKER_ROLE()
-- CURRENT_ROLE() does not change when the query passes through a view
```

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL blocks below with a note:
"No active connection detected -- copy and run this SQL in your Snowflake worksheet."

### SQL demo

```sql
-- Variable block: pre-declare all names used in this step
SET DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET R_ANALYST   = $DEMO_PREFIX || '_analyst';
SET T_ORDERS    = $DEMO_PREFIX || '.tpch.orders_sample';
SET V_ORDERS    = $DEMO_PREFIX || '.tpch.orders_view';
SET MASK_PRICE  = $DEMO_PREFIX || '.tpch.mask_order_price';

-- ============================================================
-- EXAMPLE: Masking Policies - CURRENT_ROLE() Fix
-- Continues from Masking: INVOKER_ROLE() setup (analyst role, view_creator role,
-- tpch.orders_sample, tpch.orders_view)
-- ============================================================

-- === FIX: use CURRENT_ROLE() instead of INVOKER_ROLE() ===
USE ROLE ACCOUNTADMIN;

-- Unset the policy from the column before replacing it
ALTER TABLE IDENTIFIER($T_ORDERS) MODIFY COLUMN o_totalprice UNSET MASKING POLICY;

SET g = 'CREATE OR REPLACE MASKING POLICY ' || $MASK_PRICE || ' AS ' ||
        '(val NUMBER) RETURNS NUMBER -> ' ||
        'CASE WHEN CURRENT_ROLE() = ''' || UPPER($R_ANALYST) || ''' THEN val ELSE -1 END';
EXECUTE IMMEDIATE $g;

ALTER TABLE IDENTIFIER($T_ORDERS) MODIFY COLUMN o_totalprice SET MASKING POLICY IDENTIFIER($MASK_PRICE);

-- Query through the view as analyst_role: now works correctly
SET r = 'USE ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $r;
SELECT o_orderkey, o_totalprice FROM IDENTIFIER($V_ORDERS) LIMIT 5;
-- Expected: real prices (CURRENT_ROLE = analyst role regardless of view ownership)

-- Confirm direct table query still works
SELECT o_orderkey, o_totalprice FROM IDENTIFIER($T_ORDERS) LIMIT 5;
-- Expected: real prices (CURRENT_ROLE = analyst role)
```

```sql
-- Variable block: pre-declare all names used in this step
SET DEMO_PREFIX = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_DB     = $DEMO_PREFIX;
SET DEMO_SCHEMA = $DEMO_PREFIX || '.tpch';
SET R_ANALYST   = $DEMO_PREFIX || '_analyst';
SET T_ORDERS    = $DEMO_PREFIX || '.tpch.orders_sample';
SET V_ORDERS    = $DEMO_PREFIX || '.tpch.orders_view';
SET MASK_PRICE  = $DEMO_PREFIX || '.tpch.mask_order_price';

-- ============================================================
-- EXAMPLE: Caller's Rights - Session Context
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- Shows how caller's rights proc interacts with session-based masking
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $g;
GRANT CREATE PROCEDURE ON SCHEMA IDENTIFIER($DEMO_SCHEMA) TO ROLE IDENTIFIER($R_ANALYST);

SET r = 'USE ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA tpch;

-- Caller's rights proc: reads session variable set by caller
-- Note: $SEGMENT_FILTER must exist at compile time -- set a default before CREATE
SET SEGMENT_FILTER = 'BUILDING';

CREATE OR REPLACE PROCEDURE customers_by_segment()
  RETURNS TABLE (cust_key NUMBER, name VARCHAR, segment VARCHAR, nation VARCHAR)
  LANGUAGE SQL
  EXECUTE AS CALLER
AS
BEGIN
  LET seg VARCHAR := $SEGMENT_FILTER;
  LET rs RESULTSET := (
    SELECT c_custkey, c_name, c_mktsegment, c_nationkey::VARCHAR
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
    WHERE c_mktsegment = :seg
    LIMIT 10
  );
  RETURN TABLE(rs);
END;

-- === DEMONSTRATE: caller sets a session variable, proc reads it ===
SET r = 'USE ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $r;

SET SEGMENT_FILTER = 'BUILDING';
SET c = 'CALL ' || $DEMO_SCHEMA || '.customers_by_segment()'; EXECUTE IMMEDIATE $c;
-- Expected: 10 rows where c_mktsegment = 'BUILDING'

SET SEGMENT_FILTER = 'AUTOMOBILE';
SET c = 'CALL ' || $DEMO_SCHEMA || '.customers_by_segment()'; EXECUTE IMMEDIATE $c;
-- Expected: 10 rows where c_mktsegment = 'AUTOMOBILE'

-- Key observation: inside this caller's rights proc, INVOKER_ROLE() = session role
-- (because the proc runs as the caller, not the owner)
-- So a masking policy using INVOKER_ROLE() would behave the same as CURRENT_ROLE() here
-- The difference only emerges with EXECUTE AS OWNER procs and views

-- === CLEANUP ===
USE ROLE ACCOUNTADMIN;
SET g = 'DROP PROCEDURE IF EXISTS ' || $DEMO_SCHEMA || '.customers_by_segment()'; EXECUTE IMMEDIATE $g;
DROP VIEW IF EXISTS IDENTIFIER($V_ORDERS);
DROP TABLE IF EXISTS IDENTIFIER($T_ORDERS);
DROP MASKING POLICY IF EXISTS IDENTIFIER($MASK_PRICE);
```

After running, explain what the output shows:
> Replacing `INVOKER_ROLE()` with `CURRENT_ROLE()` in the masking policy fixed the view trap.
> `CURRENT_ROLE()` is stable: it returns the session role regardless of view or proc nesting.
> Inside a caller's rights proc, `INVOKER_ROLE()` and `CURRENT_ROLE()` converge -- both return the session role.
> Inside an owner's rights proc or view, they diverge.

## What we did

- Fixed the view trap by switching the masking policy from `INVOKER_ROLE()` to `CURRENT_ROLE()`
- Confirmed that `CURRENT_ROLE()` returns the session role regardless of how the table is accessed
- Demonstrated a caller's rights stored procedure: session variable access + caller identity
- Learned that `INVOKER_ROLE()` and `CURRENT_ROLE()` converge in caller's rights context but diverge in owner's rights and view context

> Use `INVOKER_ROLE()` to enforce by object ownership.
> Use `CURRENT_ROLE()` to enforce by session identity.
> They are not interchangeable.

### Recap

Key insight: CURRENT_ROLE() returns the session role regardless of object nesting. INVOKER_ROLE() changes based on what object is running the query.

- CURRENT_ROLE() is stable across direct queries, views, procedures, and tasks.
- INVOKER_ROLE() changes each time the query passes through a different owner's object.
- For session-role-based enforcement, CURRENT_ROLE() is the correct choice.

## Mark COMPLETE

```bash
cortex ctx step done masking-current-role
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Troubleshoot?"
- Options: ["Yes, continue to Troubleshoot", "Jump to a specific concept", "Stop here"]

If yes: load `steps/troubleshoot.md`
