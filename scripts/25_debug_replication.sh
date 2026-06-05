#!/bin/bash
# ============================================================
#  Debug MySQL Replication Status
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Replication Debug ---"
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

# ---- Helper: run SQL, suppress password warning ----
mysql_q() { mysql -u "$DB_USER_IN" -p"$DB_PASS" 2>/dev/null "$@"; }

# ============================================================
# REPLICA STATUS
# ============================================================
echo "=============================="
echo "  REPLICA STATUS"
echo "=============================="
RAW=$(mysql_q -e "SHOW REPLICA STATUS\G" 2>/dev/null)

# Try legacy syntax if REPLICA not supported (MySQL < 8.0.22)
if [ -z "$RAW" ]; then
    RAW=$(mysql_q -e "SHOW SLAVE STATUS\G" 2>/dev/null)
fi

if [ -z "$RAW" ]; then
    echo "  No replication configured (empty status)"
else
    extract() {
        echo "$RAW" | grep -i "^\s*$1:" | head -1 | sed "s/.*: //"
    }

    IO_RUNNING=$(extract   "Replica_IO_Running\|Slave_IO_Running")
    SQL_RUNNING=$(extract  "Replica_SQL_Running\|Slave_SQL_Running")
    IO_STATE=$(extract     "Slave_IO_State\|Replica_IO_State")
    SQL_STATE=$(extract    "Slave_SQL_Running_State\|Replica_SQL_Running_State")
    SRC_HOST=$(extract     "Source_Host\|Master_Host")
    SRC_USER=$(extract     "Source_User\|Master_User")
    SRC_PORT=$(extract     "Source_Port\|Master_Port")
    SRC_LOG=$(extract      "Master_Log_File\|Source_Log_File")
    READ_POS=$(extract     "Read_Master_Log_Pos\|Read_Source_Log_Pos")
    RELAY_LOG=$(extract    "Relay_Log_File")
    RELAY_POS=$(extract    "Relay_Log_Pos")
    EXEC_LOG=$(extract     "Exec_Master_Log_File\|Exec_Source_Log_File\|Relay_Master_Log_File")
    EXEC_POS=$(extract     "Exec_Master_Log_Pos\|Exec_Source_Log_Pos")
    BEHIND=$(extract       "Seconds_Behind_Master\|Seconds_Behind_Source")
    LAST_IO_ERR=$(extract  "Last_IO_Error")
    LAST_SQL_ERR=$(extract "Last_SQL_Error")
    LAST_ERR=$(extract     "Last_Error")
    AUTO_POS=$(extract     "Auto_Position")
    GTID_EXEC=$(extract    "Executed_Gtid_Set")

    # Color indicators
    ok()   { printf "\e[32m%s\e[0m" "$1"; }
    warn() { printf "\e[33m%s\e[0m" "$1"; }
    err()  { printf "\e[31m%s\e[0m" "$1"; }

    io_ind=$([ "$IO_RUNNING" = "Yes" ] && ok "YES" || err "NO ($IO_RUNNING)")
    sql_ind=$([ "$SQL_RUNNING" = "Yes" ] && ok "YES" || err "NO ($SQL_RUNNING)")

    echo ""
    echo "  Connection"
    echo "    Source host : $SRC_HOST:$SRC_PORT"
    echo "    Source user : $SRC_USER"
    echo ""
    echo "  Thread state"
    printf "    IO thread   : %b\n" "$io_ind"
    [ -n "$IO_STATE"  ] && echo "    IO state    : $IO_STATE"
    printf "    SQL thread  : %b\n" "$sql_ind"
    [ -n "$SQL_STATE" ] && echo "    SQL state   : $SQL_STATE"
    echo ""
    echo "  Binlog / position"
    echo "    Reading from: $SRC_LOG  pos $READ_POS"
    echo "    Executed    : $EXEC_LOG  pos $EXEC_POS"
    echo "    Relay log   : $RELAY_LOG  pos $RELAY_POS"
    [ -n "$AUTO_POS" ] && echo "    GTID mode   : auto_position=$AUTO_POS"
    echo ""

    if [ -n "$BEHIND" ]; then
        if [ "$BEHIND" = "NULL" ]; then
            printf "  Lag           : %b\n" "$(err "NULL (IO thread not running)")"
        elif [ "$BEHIND" -gt 300 ] 2>/dev/null; then
            printf "  Lag           : %b\n" "$(warn "${BEHIND}s  -- BEHIND")"
        elif [ "$BEHIND" -gt 0 ] 2>/dev/null; then
            printf "  Lag           : %b\n" "$(warn "${BEHIND}s")"
        else
            printf "  Lag           : %b\n" "$(ok "${BEHIND}s  -- in sync")"
        fi
    fi

    echo ""
    if [ -n "$LAST_IO_ERR" ] && [ "$LAST_IO_ERR" != "" ]; then
        printf "  IO Error      : %b\n" "$(err "$LAST_IO_ERR")"
    fi
    if [ -n "$LAST_SQL_ERR" ] && [ "$LAST_SQL_ERR" != "" ]; then
        printf "  SQL Error     : %b\n" "$(err "$LAST_SQL_ERR")"
    fi
    if [ -n "$LAST_ERR" ] && [ "$LAST_ERR" != "" ]; then
        printf "  Last Error    : %b\n" "$(err "$LAST_ERR")"
    fi
    if [ -n "$GTID_EXEC" ] && [ "$GTID_EXEC" != "" ]; then
        echo "  Executed GTIDs: $GTID_EXEC"
    fi
fi

# ============================================================
# GLOBAL STATUS — replication counters
# ============================================================
echo ""
echo "=============================="
echo "  GLOBAL STATUS (replication counters)"
echo "=============================="
mysql_q -e "
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
    'Rpl_semi_sync_replica_status',
    'Rpl_semi_sync_slave_status',
    'Com_commit',
    'Com_rollback',
    'Slave_running',
    'Replica_running'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null | column -t | sed 's/^/  /'

# ============================================================
# PROCESSLIST — replication threads
# ============================================================
echo ""
echo "=============================="
echo "  ACTIVE REPLICATION THREADS"
echo "=============================="
mysql_q -e "
SELECT ID, USER, HOST, COMMAND, TIME, STATE
FROM information_schema.PROCESSLIST
WHERE USER IN ('repl','system user','event_scheduler')
   OR COMMAND IN ('Binlog Dump','Binlog Dump GTID')
ORDER BY COMMAND;
" 2>/dev/null | column -t | sed 's/^/  /'

# ============================================================
# RECENT ERRORS from error log (if accessible)
# ============================================================
ERROR_LOG=$(mysql_q -e "SHOW VARIABLES LIKE 'log_error';" 2>/dev/null \
    | tail -1 | awk '{print $2}')

if [ -n "$ERROR_LOG" ] && [ -f "$ERROR_LOG" ]; then
    echo ""
    echo "=============================="
    echo "  RECENT REPLICATION ERRORS (error log)"
    echo "=============================="
    ERRORS=$(grep -i "replica\|slave\|replication" "$ERROR_LOG" 2>/dev/null \
        | grep -v "\[Warning\]" \
        | grep -v "deprecated" \
        | tail -10)
    if [ -n "$ERRORS" ]; then
        echo "$ERRORS" | sed 's/^/  /'
    else
        echo "  No replication errors found (deprecation warnings suppressed)."
    fi
fi

echo ""
echo "  Tip: run 'journalctl -u mysql' or check $ERROR_LOG for full details."
echo ""
