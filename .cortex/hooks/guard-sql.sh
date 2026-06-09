#!/usr/bin/env bash
# PreToolUse hook: block destructive DDL outside the skill demo prefix.
# Stdin: full hook context JSON; tool_input.sql holds the SQL string.
#
# Allow conditions (checked in order, any one is sufficient):
#   1. SQL uses IDENTIFIER($var) -- ALL skill cleanup steps use session variable dereference
#   2. SQL contains the user-specific demo prefix derived from the active Snowflake connection
#      e.g. kameshs_executor_role_workshop (computed dynamically, not hardcoded)
# Block: anything else with DROP DATABASE, DROP SCHEMA, TRUNCATE TABLE, or DELETE FROM

input=$(cat)
sql=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('sql', ''))
except Exception:
    print('')
" 2>/dev/null | tr '[:lower:]' '[:upper:]')

# Lazy-compute demo prefix only when a destructive pattern is found
get_demo_prefix() {
    python3 -c "
import json, subprocess, sys
try:
    out = subprocess.check_output(['cortex', 'connections', 'list'], text=True)
    data = json.loads(out)
    active = data.get('active_connection', '')
    user = data.get('connections', {}).get(active, {}).get('user', '').lower()
    print((user + '_executor_role_workshop').upper() if user else '')
except Exception:
    print('')
" 2>/dev/null
}

for pattern in "DROP DATABASE" "DROP SCHEMA" "TRUNCATE TABLE" "DELETE FROM"; do
    if echo "$sql" | grep -q "$pattern"; then
        # Allow: session-variable dereference -- all skill cleanup uses IDENTIFIER($DEMO_DB) etc.
        if echo "$sql" | grep -qE 'IDENTIFIER\(\$[A-Z_]+\)'; then
            exit 0
        fi
        # Allow: user-specific demo prefix (e.g. KAMESHS_EXECUTOR_ROLE_WORKSHOP)
        demo_prefix=$(get_demo_prefix)
        if [ -n "$demo_prefix" ] && echo "$sql" | grep -q "$demo_prefix"; then
            exit 0
        fi
        echo "Blocked: '$pattern' outside demo prefix. Use the skill's cleanup step or troubleshoot step to drop objects." >&2
        exit 2
    fi
done

exit 0
