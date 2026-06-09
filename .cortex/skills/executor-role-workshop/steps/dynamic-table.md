---
name: executor-role-workshop-dynamic-table
description: Dynamic tables - EXECUTE AS USER to pin a named user identity for refresh
---

## Mark IN_PROGRESS

```bash
cortex ctx step start dynamic-table
```

> Call enter_plan_mode before presenting.

# Dynamic Tables: The Ghost User Problem

## Why this matters

Dynamic tables refresh in the background. By default, the refresh runs as an internal SYSTEM user, not as the owner's role or username.

That is fine for most queries. It becomes a problem the moment your masking policies or row
access policies use `CURRENT_USER()`. The default refresh executor is SYSTEM, so policies that check `CURRENT_USER()` will not match any named user. The data comes back
fully masked or excluded.

The fix is `EXECUTE AS USER`, added in February 2026. It lets you pin the refresh to a
named service user. The dynamic table has a user context distinct from the role context.
SYSTEM user is the default; named user is optional but required for user-scoped logic.

> `EXECUTE AS USER` is not about security. It is about identity. Policies need to know who
> is running the refresh. Snowflake needs to be told.

### Theorem

> By default, a dynamic table refresh runs as an internal `SYSTEM` user, not as the owner role or the owner's username. Policies that check `CURRENT_USER()` will mask all data unless `EXECUTE AS USER` pins a named identity.

> SQL note: `EXECUTE AS USER` requires a literal username, not `IDENTIFIER($var)`. Session variables do not exist in the DT refresh context. Use a Snowflake Scripting block to build the `CREATE DYNAMIC TABLE` statement with all names embedded as literals.

## What we'll do

1. Create `transform_role` and a service user `svc_transform`
2. Grant `IMPERSONATE ON USER svc_transform` to `transform_role`
3. Create a masking policy that checks `CURRENT_USER()` -- only allows `SVC_TRANSFORM`
4. Apply the policy to a base table
5. Create a dynamic table **with** `EXECUTE AS USER svc_transform`
6. Refresh and verify: real prices appear (executor = SVC_TRANSFORM)
7. Contrast: without `EXECUTE AS USER`, the refresh runs as SYSTEM and returns masked values

### Reflect

A dynamic table refreshes in the background. The masking policy on the source table checks `CURRENT_USER()`. You own this dynamic table. What user does the refresh run as -- your username, your role name, or something else entirely? Will the masking policy unmask the data? Make a prediction, then run the SQL.

### What to expect

```sql
-- Without EXECUTE AS USER: refresh runs as SYSTEM user
SELECT * FROM <your_prefix>.tpch.dt_revenue LIMIT 5;
-- Expected: all net_revenue = -1
-- (CURRENT_USER() inside the refresh = SYSTEM, policy masks everything)

-- With EXECUTE AS USER <your_prefix>_svc: refresh runs as named service user
SELECT * FROM <your_prefix>.tpch.dt_revenue LIMIT 5;
-- Expected: real net_revenue values
-- (CURRENT_USER() inside the refresh = <your_prefix>_svc, policy allows)
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
SET DEMO_DB     = $DEMO_PREFIX;
SET DEMO_SCHEMA = $DEMO_PREFIX || '.tpch';
SET R_TRANSFORM = $DEMO_PREFIX || '_transform';
SET SVC_USER    = $DEMO_PREFIX || '_svc';
SET T_PRICES    = $DEMO_PREFIX || '.tpch.lineitem_prices';
SET DT_REVENUE  = $DEMO_PREFIX || '.tpch.dt_revenue';
SET MASK_PRICE  = $DEMO_PREFIX || '.tpch.mask_price';

-- ============================================================
-- EXAMPLE: Dynamic Tables - EXECUTE AS USER
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

-- Service user to pin the refresh identity
-- (transform role was created in the setup step)
SET g = 'CREATE USER IF NOT EXISTS ' || $SVC_USER || ' DEFAULT_ROLE = ' || $R_TRANSFORM || ' MUST_CHANGE_PASSWORD = FALSE'; EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_TRANSFORM || ' TO USER ' || $SVC_USER; EXECUTE IMMEDIATE $g;

-- Give the owner role IMPERSONATE on the service user
GRANT IMPERSONATE ON USER IDENTIFIER($SVC_USER) TO ROLE IDENTIFIER($R_TRANSFORM);

SET r = 'USE ROLE ' || $R_TRANSFORM; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;

-- Masking policy: only the service user sees real prices
-- Policy body embeds the literal username at creation time via EXECUTE IMMEDIATE
SET g = 'CREATE OR REPLACE MASKING POLICY ' || $MASK_PRICE || ' AS ' ||
        '(val NUMBER) RETURNS NUMBER -> ' ||
        'CASE WHEN CURRENT_USER() = ''' || UPPER($SVC_USER) || ''' THEN val ELSE -1 END';
EXECUTE IMMEDIATE $g;

-- Base table with the policy applied
CREATE OR REPLACE TABLE IDENTIFIER($T_PRICES) AS
SELECT l_orderkey, l_extendedprice, l_discount
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
LIMIT 1000;

ALTER TABLE IDENTIFIER($T_PRICES)
  MODIFY COLUMN l_extendedprice
  SET MASKING POLICY IDENTIFIER($MASK_PRICE);

-- === DEMONSTRATE: dynamic table WITH EXECUTE AS USER ===
-- IMPORTANT: EXECUTE AS USER takes a literal identifier, not IDENTIFIER($var).
-- Session variables don't exist in the DT refresh context.
-- Use a Snowflake Scripting block to embed all literal names at creation time.
EXECUTE IMMEDIATE $$
DECLARE
  svc   VARCHAR DEFAULT LOWER(CURRENT_USER()) || '_executor_role_workshop_svc';
  src   VARCHAR DEFAULT LOWER(CURRENT_USER()) || '_executor_role_workshop.tpch.lineitem_prices';
  tgt   VARCHAR DEFAULT LOWER(CURRENT_USER()) || '_executor_role_workshop.tpch.dt_revenue';
  sql   VARCHAR DEFAULT '';
BEGIN
  sql := 'CREATE OR REPLACE DYNAMIC TABLE ' || tgt ||
         ' TARGET_LAG = ''1 hour'' WAREHOUSE = COMPUTE_WH' ||
         ' INITIALIZE = ON_SCHEDULE' ||
         ' EXECUTE AS USER ' || svc ||
         ' AS SELECT l_orderkey,' ||
         ' SUM(l_extendedprice * (1 - l_discount)) AS net_revenue' ||
         ' FROM ' || src || ' GROUP BY l_orderkey';
  EXECUTE IMMEDIATE sql;
END;
$$;

ALTER DYNAMIC TABLE IDENTIFIER($DT_REVENUE) REFRESH;
-- Expected: refresh completes, data shows real prices (CURRENT_USER = service user)

SELECT * FROM IDENTIFIER($DT_REVENUE) LIMIT 5;
-- Expected: net_revenue shows real numbers, not -1

-- === CONTRAST: without EXECUTE AS USER ===
-- If you create the same DT without EXECUTE AS USER, the refresh runs as SYSTEM.
-- CURRENT_USER() != service user so the masking policy returns -1 for all rows.
-- The DT refreshes successfully but all revenue values are -1.

-- === CLEANUP ===
USE ROLE ACCOUNTADMIN;
DROP DYNAMIC TABLE IF EXISTS IDENTIFIER($DT_REVENUE);
DROP TABLE IF EXISTS IDENTIFIER($T_PRICES);
DROP MASKING POLICY IF EXISTS IDENTIFIER($MASK_PRICE);
REVOKE IMPERSONATE ON USER IDENTIFIER($SVC_USER) FROM ROLE IDENTIFIER($R_TRANSFORM);
SET g = 'DROP USER IF EXISTS ' || $SVC_USER; EXECUTE IMMEDIATE $g;
```

After running, explain what the output shows:
> `dt_revenue` refreshed and returned real `net_revenue` values because the executor was the named service user, not an anonymous SYSTEM user.
> The masking policy checked `CURRENT_USER()` and found the named service user.
> Without `EXECUTE AS USER`, all values would be -1.

## What we did

- Created a named service user `svc_transform` with a masking policy that checks `CURRENT_USER()`
- Created a dynamic table with `EXECUTE AS USER svc_transform`
- Verified that the refresh runs as the named user -- policies resolve correctly
- Learned that the default executor for dynamic table refreshes is an internal SYSTEM user
- `EXECUTE AS USER` is required whenever policies or audit trails need a named user identity

### Recap

Key insight: dynamic table refreshes run as an internal SYSTEM user by default. Policies that check CURRENT_USER() will not match any named user unless you pin the refresh identity with EXECUTE AS USER.

- The default refresh executor is SYSTEM, not the owner role's user.
- EXECUTE AS USER pins a named service user as the refresh identity.
- Use this whenever masking policies or row access policies check CURRENT_USER() on tables accessed by a dynamic table.

## Mark COMPLETE

```bash
cortex ctx step done dynamic-table
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Masking: INVOKER_ROLE()?"
- Options: ["Yes, continue to Masking: INVOKER_ROLE()", "Jump to a specific concept", "Stop here"]

If yes: load `steps/masking-invoker.md`
