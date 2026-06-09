---
name: executor-role-workshop-owners-rights
description: Owner's rights stored procedures - privilege delegation via EXECUTE AS OWNER
---

## Mark IN_PROGRESS

```bash
cortex ctx step start owners-rights
```

> Call enter_plan_mode before presenting.

# Owner's Rights: Privilege Delegation

## Why this matters

Owner's rights is not a workaround. It is the access model.

You have a `DATA_ENGINEER_ROLE` that owns sensitive order data. You have an `ANALYST_ROLE` that
needs to run a specific, controlled operation on that data. But you do not want to grant
`ANALYST_ROLE` direct SELECT privileges on raw data.

Owner's rights stored procedures solve this exactly. The procedure runs with the **owner's grants**,
not the caller's. The analyst calls the procedure -- the data engineer's grants do the actual work.
The analyst never touches the table directly.

This is privilege delegation: the owner sets the boundaries by what the procedure does, not by
what the caller is allowed to do.

### Theorem

> A role with no direct table access can get results from that table by calling a procedure owned by a role that does have access. The caller needs only `USAGE` on the procedure.

## What we'll do

1. Create `data_engineer_role` (owns the data and the procedure) and `analyst_role` (can only call the procedure)
2. Set up `executor_demo` database with TPCH data access for `data_engineer_role`
3. Create stored procedure `high_value_orders` with `EXECUTE AS OWNER`
4. Grant `analyst_role` only `USAGE` on the procedure (no table access)
5. Demonstrate: analyst calls the procedure and gets results
6. Contrast: analyst queries the table directly and gets an access error

### Reflect

The analyst_role has no SELECT privilege on SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS. The data_eng_role does, and it owns the procedure. When the analyst calls the procedure, will it return rows or fail with an access error? Form your answer, then run the SQL.

### What to expect

```sql
-- Will fail: analyst queries the table directly
-- Session role: <your_prefix>_analyst (no SELECT on ORDERS)
SELECT o_orderkey, o_totalprice FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 5;
-- Expected: SQL access control error: privilege [SELECT] not granted

-- Will pass: analyst calls the owner's rights procedure
CALL <your_prefix>.tpch.high_value_orders(500000);
-- Expected: 10 rows of high-value orders
-- The procedure runs as data_eng (the owner), not as analyst (the caller)
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
SET R_DATA_ENG  = $DEMO_PREFIX || '_data_eng';
SET R_ANALYST   = $DEMO_PREFIX || '_analyst';

-- ============================================================
-- Owner's Rights Demo: Privilege Delegation
-- Uses: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- ============================================================

-- === SETUP ===
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS IDENTIFIER($R_DATA_ENG);
CREATE ROLE IF NOT EXISTS IDENTIFIER($R_ANALYST);
SET g = 'GRANT ROLE ' || $R_DATA_ENG || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;
SET g = 'GRANT ROLE ' || $R_ANALYST  || ' TO USER ' || CURRENT_USER(); EXECUTE IMMEDIATE $g;

-- Give data_eng access to the source data
SET g = 'GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE ' || $R_DATA_ENG; EXECUTE IMMEDIATE $g;

-- Give data_eng ownership of the demo schema
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB)     TO ROLE IDENTIFIER($R_DATA_ENG);
GRANT ALL   ON SCHEMA IDENTIFIER($DEMO_SCHEMA)   TO ROLE IDENTIFIER($R_DATA_ENG);

-- Analyst gets no access to source data -- only the proc
GRANT USAGE ON DATABASE IDENTIFIER($DEMO_DB)     TO ROLE IDENTIFIER($R_ANALYST);
GRANT USAGE ON SCHEMA IDENTIFIER($DEMO_SCHEMA)   TO ROLE IDENTIFIER($R_ANALYST);

-- Create the proc as data_eng (owner's rights by default)
SET r = 'USE ROLE ' || $R_DATA_ENG; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA tpch;

CREATE OR REPLACE PROCEDURE high_value_orders(min_price FLOAT)
  RETURNS TABLE (order_key NUMBER, total_price FLOAT, status VARCHAR)
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
BEGIN
  LET rs RESULTSET := (
    SELECT o_orderkey::NUMBER        AS order_key,
           o_totalprice::FLOAT       AS total_price,
           o_orderstatus::VARCHAR    AS status
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
    WHERE o_totalprice > :min_price
    ORDER BY o_totalprice DESC
    LIMIT 10
  );
  RETURN TABLE(rs);
END;

SET g = 'GRANT USAGE ON PROCEDURE ' || $DEMO_SCHEMA || '.high_value_orders(FLOAT) TO ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $g;

-- === DEMONSTRATE: analyst calls the proc and gets data ===
SET r = 'USE ROLE ' || $R_ANALYST; EXECUTE IMMEDIATE $r;
USE WAREHOUSE COMPUTE_WH;

SET c = 'CALL ' || $DEMO_SCHEMA || '.high_value_orders(500000)'; EXECUTE IMMEDIATE $c;
-- Expected: 10 rows of high-value orders
-- The analyst has NO direct access to TPCH_SF1.ORDERS -- but the proc owner does

-- === CONTRAST: analyst queries the table directly ===
SELECT o_orderkey, o_totalprice
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 5;
-- Expected: SQL access control error: privilege [SELECT] not granted
```

After running, explain what the output shows:
> `high_value_orders` returned 10 rows for the analyst.
> The direct SELECT on `TPCH_SF1.ORDERS` failed with an access error.
> Same role, same session -- but the procedure ran as the data engineer's grants, not the analyst's.

## What we did

- Created `data_engineer_role` with SELECT on source data and `analyst_role` with no table access
- Created `high_value_orders` procedure with `EXECUTE AS OWNER`
- Proved that `analyst_role` can call the procedure and get results
- Proved that `analyst_role` cannot query the table directly
- Demonstrated privilege delegation: owner sets the ceiling, caller works within it

Owner's rights is not a workaround. It is the access model.

### Recap

Key insight: the procedure runs as the data engineer's role, not the analyst's. The analyst calls it; the owner's grants do the actual work.

- `EXECUTE AS OWNER` means the procedure uses the owner role's privileges for every SQL statement inside it.
- The caller only needs USAGE on the procedure. No table access is required.
- Owner's rights is the standard model for privilege delegation in Snowflake. It is not a workaround.

> **A third mode: `EXECUTE AS RESTRICTED CALLER` (Native Apps only)**
> For Native App providers who need access to consumer account objects, Snowflake offers a third mode.
> The consumer explicitly authorizes it with `GRANT CALLER USAGE ON DATABASE consumer_db TO APPLICATION my_app;`.
> Standard procedures use OWNER or CALLER. RESTRICTED CALLER is a Native Apps boundary mechanism.
> See: [Restricted Caller's Rights docs](https://docs.snowflake.com/en/developer-guide/restricted-callers-rights)

## Mark COMPLETE

```bash
cortex ctx step done owners-rights
```

## Next

Use `ask_user_question`:
- Header: "Next"
- Question: "Continue to Execute Task?"
- Options: ["Yes, continue to Execute Task", "Jump to a specific concept", "Stop here"]
- If yes: load steps/execute-task.md
