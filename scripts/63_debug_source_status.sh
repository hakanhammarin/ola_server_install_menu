#!/bin/bash
# ============================================================
#  Debug MySQL Master (Source) Status
#  Shows binary log position, connected replicas, and binlog config
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Master / Source Status ---"
echo ""

# ---- MySQL credentials ----
DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user   [%s]: " "$DEFAULT_DB_USER"
read -r input_user
DB_USER_IN="${input_user:-$DEFAULT_DB_USER}"

printf "  MySQL password: "
read -rs DB_PASS
echo ""
echo ""

mysql_q() { mysql -u "$DB_USER_IN" -p"$DB_PASS" 2>/dev/null "$@"; }

# ============================================================
# BINARY LOG STATUS  (SHOW BINARY LOG STATUS, fallback to SHOW MASTER STATUS)
# ============================================================
echo "=============================="
echo "  BINARY LOG STATUS"
echo "=============================="

RAW=$(mysql_q -e "SHOW BINARY LOG STATUS\G" 2>/dev/null)
if [ -z "$RAW" ]; then
    RAW=$(mysql_q -e "SHOW MASTER STATUS\G" 2>/dev/null)
fi

if [ -z "$RAW" ]; then
    echo "  No binary log status returned."
    echo "  Binary logging may be disabled — check: SHOW VARIABLES LIKE 'log_bin';"
else
    extract() { echo "$RAW" | grep -i "^\s*$1:" | head -1 | sed "s/.*: //"; }

    BINLOG_FILE=$(extract  "File")
    BINLOG_POS=$(extract   "Position")
    BINLOG_DBS=$(extract   "Binlog_Do_DB")
    IGNORE_DBS=$(extract   "Binlog_Ignore_DB")
    GTID_SET=$(extract     "Executed_Gtid_Set")

    echo ""
    echo "  Current position"
    echo "    File     : $BINLOG_FILE"
    echo "    Position : $BINLOG_POS"
    [ -n "$BINLOG_DBS"  ] && echo "    Do DB    : $BINLOG_DBS"
    [ -n "$IGNORE_DBS"  ] && echo "    Ignore DB: $IGNORE_DBS"
    if [ -n "$GTID_SET" ] && [ "$GTID_SET" != "" ]; then
        echo ""
        echo "  Executed GTIDs:"
        echo "    $GTID_SET"
    fi
fi

# ============================================================
# BINARY LOG FILES
# ============================================================
echo ""
echo "=============================="
echo "  BINARY LOG FILES"
echo "=============================="
mysql_q -e "SHOW BINARY LOGS;" 2>/dev/null \
    | awk 'NR==1{printf "  %-30s  %-12s  %s\n", $1, $2, $3; next}
           {printf "  %-30s  %-12s  %s\n", $1, $2, $3}' \
    | sed 's/^//' \
    | head -20

# ============================================================
# CONNECTED REPLICAS
# ============================================================
echo ""
echo "=============================="
echo "  CONNECTED REPLICAS"
echo "=============================="

# SHOW REPLICA HOSTS (8.0.22+), fallback to SHOW SLAVE HOSTS
REPLICA_HOSTS=$(mysql_q -e "SHOW REPLICA HOSTS\G" 2>/dev/null)
if [ -z "$REPLICA_HOSTS" ]; then
    REPLICA_HOSTS=$(mysql_q -e "SHOW SLAVE HOSTS\G" 2>/dev/null)
fi

if [ -z "$REPLICA_HOSTS" ]; then
    echo "  No replicas registered (report_host may not be set on replica)."
else
    echo "$REPLICA_HOSTS" | grep -E "Server_id|Host|Port|Master_id|Source_id" | sed 's/^/  /'
fi

echo ""
echo "  Active Binlog Dump threads (replicas currently streaming):"
mysql_q -e "
SELECT ID, USER, HOST, TIME, STATE
FROM information_schema.PROCESSLIST
WHERE COMMAND IN ('Binlog Dump', 'Binlog Dump GTID')
ORDER BY ID;
" 2>/dev/null | column -t | sed 's/^/  /'

# ============================================================
# BINLOG-RELATED VARIABLES
# ============================================================
echo ""
echo "=============================="
echo "  BINLOG CONFIGURATION"
echo "=============================="
mysql_q -e "
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_variables
WHERE VARIABLE_NAME IN (
    'log_bin',
    'binlog_format',
    'binlog_row_image',
    'log_replica_updates',
    'log_slave_updates',
    'replica_skip_errors',
    'slave_skip_errors',
    'binlog_expire_logs_seconds',
    'expire_logs_days',
    'max_binlog_size',
    'sync_binlog',
    'gtid_mode',
    'enforce_gtid_consistency',
    'server_id'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null | column -t | sed 's/^/  /'

# ============================================================
# RECENT BINLOG ERRORS from error log
# ============================================================
ERROR_LOG=$(mysql_q -e "SHOW VARIABLES LIKE 'log_error';" 2>/dev/null \
    | tail -1 | awk '{print $2}')

if [ -n "$ERROR_LOG" ] && [ -f "$ERROR_LOG" ]; then
    echo ""
    echo "=============================="
    echo "  RECENT BINLOG/SOURCE ERRORS (error log)"
    echo "=============================="
    ERRORS=$(grep -i "binlog\|master\|source\|dump thread" "$ERROR_LOG" 2>/dev/null \
        | grep -v "\[Warning\]" \
        | grep -v "deprecated" \
        | tail -10)
    if [ -n "$ERRORS" ]; then
        echo "$ERRORS" | sed 's/^/  /'
    else
        echo "  No binlog/source errors found."
    fi
fi

echo ""
echo "  Tip: use option 62 to check the replica side."
echo "  Tip: 'journalctl -u mysql' for the full MySQL error log."
echo ""
