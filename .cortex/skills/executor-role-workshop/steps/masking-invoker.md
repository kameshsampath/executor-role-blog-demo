---
name: executor-role-workshop-masking-invoker
description: Masking policies - INVOKER_ROLE() returns the executing object's owner, not the session role
---

## Mark IN_PROGRESS

```bash
cortex ctx step start masking-invoker
```

> Call enter_plan_mode before presenting.

# Masking: INVOKER_ROLE()

## Why this matters

Masking policy bodies are special -- they run in a different context from regular SQL.

You apply a masking policy that uses `INVOKER_ROLE()`. The policy says: if the invoker is the
ANALYST role, show the data. Otherwise, mask it.

You run as ANALYST. You query the table directly. Data is visible. Expected.

You query the same data through a view. Data is masked -- even though the view was created by
a role that should have access. Wait. The ANALYST's session role did not change. What happened?

`INVOKER_ROLE()` inside a masking policy does not return your session role when you query through
a view. It returns the **view owner's role**. Not yours.

This is the view trap: a policy that works correctly on direct table access silently breaks when
the table is accessed through a view owned by a different role.

`INVOKER_ROLE()` is the right choice when you want to enforce based on who **owns the object
executing the query**. It is the wrong choice when you want to enforce based on who is
**running the session**.

### Theorem

> `INVOKER_ROLE()` inside a masking policy returns the role of the object running the query, not the session role. When a query passes through a view, `INVOKER_ROLE()` returns the view owner's role, not yours.

## What we'll do

1. Create `analyst_role` and `view_creator_role`
2. Create a masking policy using `INVOKER_ROLE()` on a price column
3. Create a view owned by `view_creator_role` over the masked table
4. Query as `analyst_role`: direct table query shows real prices
5. Query as `analyst_role` through the view: prices are masked -- because `INVOKER_ROLE()` = `view_creator_role`
6. Observe the trap

### Reflect

The analyst role queries a table directly and sees real prices. The same analyst role queries the same table through a view. The masking policy uses INVOKER_ROLE(). The analyst's session role has not changed. Will the view query return real prices or masked values? Think about why, then run the SQL.

### What to expect

```sql
-- Will pass (real prices): _analyst queries the table directly
-- INVOKER_ROLE() = <your_prefix>_analyst -> policy condition matches -> real values

-- Will return masked (-1): _analyst queries through the view
-- INVOKER_ROLE() = <your_prefix>_view_creator (the view owner) -> policy fails -> -1
-- Your session role is still _analyst. But INVOKER_ROLE() follows the object, not your session.
```

> Call exit_plan_mode after What to expect.

## Execution

### Check connection

Run `cortex connections list`. If no active connection, show the SQL blocks below with a note:
"No active connection detected -- copy and run this SQL in your Snowflake worksheet."

### SQL demo

```sql
-- Variable block: pre-declare all names used in this step
SET DEMO_PREFIX    = LOWER(CURRENT_USER()) || '_executor_role_workshop';
SET DEMO_SCHEMA    = $DEMO_PREFIX || '.tpch';
SET R_ANALYST      = $DEMO_PREFIX || '_analyst';
SET R_VIEW_CREATOR = $DEMO_PREFIX || '_view_creator';
SET T_ORDERS       = $DEMO_PREFIX || '.tpch.orders_sample';
SET V_ORDERS       = $DEMO_PREFIX || '.tpch.orders_view';
SET MASK_PRICE     = $DEMO_PREFIX || '.tpch.mask_order_price';

-- ============================================================
-- EXAMPLE: Masking Policies - INVOKER_ROLE and the View Trap
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

-- analyst_role and view_creator_role were created in the setup step
-- Grant SNOWFLAKE_SAMPLE_DATA access needed for this demo
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_VIEW_CREATOR; EXECUTE IMMEDIATE $g;

-- Masking policy using INVOKER_ROLE
-- Policy body embeds the literal role name at creation time via EXECUTE IMMEDIATE
SET g = 'CREATE OR REPLACE MASKING POLICY ' || $MASK_PRICE || ' AS ' ||
        '(val NUMBER) RETURNS NUMBER -> ' ||
        'CASE WHEN INVOKER_ROLE() = ''' || UPPER($R_ANALYST) || ''' THEN val ELSE -1 END';
EXECUTE IMMEDIATE $g;

-- Create a base table as view_creator_role
SET r = 'USE ROLE ' || $R_VIEW_CREATOR; EXECUTE IMMEDIATE $r;
CREATE OR REPLACE TABLE IDENTIFIER($T_ORDERS) AS
SELECT o_orderkey, o_custkey, o_totalprice, o_orderstatus
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 100;

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON TABLE IDENTIFIER($T_ORDERS) TO ROLE IDENTIFIER($R_ANALYST);
GRANT ALL    ON TABLE IDENTIFIER($T_ORDERS) TO ROLE IDENTIFIER($R_VIEW_CREATOR);

ALTER TABLE IDENTIFIER($T_ORDERS)
  MODIFY COLUMN o_totalprice
  SET MASKING POLICY IDENTIFIER($MASK_PRICE);

-- Create a view owned by view_creator_role (NOT analyst_role)
SET r = 'USE ROLE ' || $R_VIEW_CREATOR; EXECUTE IMMEDIATE $r;
CREATE OR REPLACE VIEW IDENTIFIER($V_ORDERS) AS
SELECT * FROM IDENTIFIER($T_ORDERS);

USE ROLE ACCOUNTADMIN;
GRANT SELECT ON VIEW IDENTIFIER($V_ORDERS) TO ROLE IDENTIFIER($R_ANALYST);

-- === DEMONSTRATE: analyst queries the table directly ===
SET r = 'USE ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;

SELECT o_orderkey, o_totalprice FROM IDENTIFIER($T_ORDERS) LIMIT 5;
-- Expected: real prices (INVOKER_ROLE = analyst role, policy returns val)

-- === CONTRAST: analyst queries through the view ===
SELECT o_orderkey, o_totalprice FROM IDENTIFIER($V_ORDERS) LIMIT 5;
-- Expected: -1 for all prices (INVOKER_ROLE = view_creator_role, not analyst role)
-- The analyst's session role is analyst_role -- but INVOKER_ROLE returns view_creator_role
```

After running, explain what the output shows:
> Direct table query returned real prices: `INVOKER_ROLE()` = analyst role.
> View query returned -1: `INVOKER_ROLE()` = view creator role (the view's owner).
> Same user, same session role, different object -- different executor.

## What we did

- Created a masking policy using `INVOKER_ROLE()` for enforcement
- Proved that direct table queries evaluate `INVOKER_ROLE()` as the session role
- Proved that view queries evaluate `INVOKER_ROLE()` as the view owner's role
- Exposed the view trap: `INVOKER_ROLE()` is about the executing object's owner, not the session

Use `INVOKER_ROLE()` when you want to enforce based on **who owns the executing object**.
Masking: CURRENT_ROLE() shows when `CURRENT_ROLE()` is the better choice.

### Recap

Key insight: INVOKER_ROLE() inside a masking policy returns the owner of the object running the query, not the session role. Through a view, it returns the view owner's role.

- Direct table access: INVOKER_ROLE() = your session role.
- View access: INVOKER_ROLE() = the view owner's role.
- Use INVOKER_ROLE() when you want to enforce based on who owns the executing object, not who is running the session.

## Mark COMPLETE

```bash
cortex ctx step done masking-invoker
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Masking: CURRENT_ROLE()?"
- Options: ["Yes, continue to Masking: CURRENT_ROLE()", "Jump to a specific concept", "Stop here"]

If yes: load `steps/masking-current-role.md`
