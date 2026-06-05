#!/bin/bash
# ============================================================
#  Re-initialize replication on the replica (no restore)
#  Use this to fix typos or reconfigure after option 9.
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
REPL_PASS_FILE="$HOME/.10mila_repl.pass"

source "$CONFIG_FILE"

grep -q "^REPL_SOURCE_HOST=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_HOST=" >> "$CONFIG_FILE"
grep -q "^REPL_SOURCE_USER=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_USER=repl" >> "$CONFIG_FILE"
grep -q "^REPL_SOURCE_PORT=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_PORT=3306" >> "$CONFIG_FILE"
source "$CONFIG_FILE"

echo "--- Re-initialize Replication ---"
echo ""

# ---- MySQL credentials ----
DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user   [%s]: " "$DEFAULT_DB_USER"
read -r input_user
DB_USER_IN="${input_user:-$DEFAULT_DB_USER}"

printf "  MySQL password: "
read -rs DB_PASS
echo ""

mysql_q() { mysql -u "$DB_USER_IN" -p"$DB_PASS" 2>/dev/null "$@"; }

# ---- Show current state ----
echo ""
echo "  Current replica state:"
RAW=$(mysql_q -e "SHOW REPLICA STATUS\G" 2>/dev/null)
[ -z "$RAW" ] && RAW=$(mysql_q -e "SHOW SLAVE STATUS\G" 2>/dev/null)

if [ -n "$RAW" ]; then
    echo "$RAW" | grep -E "Source_Host|Master_Host|Source_User|Master_User|Source_Log_File|Master_Log_File|Exec_Master_Log_Pos|Exec_Source_Log_Pos|Read_Master_Log_Pos|Read_Source_Log_Pos|Replica_IO_Running|Slave_IO_Running|Replica_SQL_Running|Slave_SQL_Running|Last_IO_Error|Last_SQL_Error" \
        | sed 's/^/    /'
else
    echo "    (no replication configured yet)"
fi

# ---- Replication source prompts ----
echo ""
echo "--- New replication settings ---"

DEFAULT_SRC_HOST="${REPL_SOURCE_HOST:-}"
printf "  SOURCE_HOST  [%s]: " "$DEFAULT_SRC_HOST"
read -r input_src_host
SRC_HOST="${input_src_host:-$DEFAULT_SRC_HOST}"
if [ -z "$SRC_HOST" ]; then echo "  ERROR: SOURCE_HOST required."; exit 1; fi

DEFAULT_SRC_USER="${REPL_SOURCE_USER:-repl}"
printf "  SOURCE_USER  [%s]: " "$DEFAULT_SRC_USER"
read -r input_src_user
SRC_USER="${input_src_user:-$DEFAULT_SRC_USER}"

DEFAULT_SRC_PORT="${REPL_SOURCE_PORT:-3306}"
printf "  SOURCE_PORT  [%s]: " "$DEFAULT_SRC_PORT"
read -r input_src_port
SRC_PORT="${input_src_port:-$DEFAULT_SRC_PORT}"

printf "  SOURCE_LOG_FILE: "
read -r SRC_LOG_FILE
if [ -z "$SRC_LOG_FILE" ]; then echo "  ERROR: SOURCE_LOG_FILE required."; exit 1; fi

printf "  SOURCE_LOG_POS: "
read -r SRC_LOG_POS
if [ -z "$SRC_LOG_POS" ]; then echo "  ERROR: SOURCE_LOG_POS required."; exit 1; fi

if [ -f "$REPL_PASS_FILE" ]; then
    printf "  SOURCE_PASSWORD [stored, press Enter to reuse or type new]: "
    read -rs input_repl_pass
    echo ""
    SRC_PASS="${input_repl_pass:-$(cat "$REPL_PASS_FILE")}"
else
    printf "  SOURCE_PASSWORD: "
    read -rs SRC_PASS
    echo ""
fi

# ---- Confirm ----
echo ""
echo "  Will run:"
echo "    STOP REPLICA"
echo "    RESET REPLICA ALL"
echo "    CHANGE REPLICATION SOURCE TO"
echo "      SOURCE_HOST='$SRC_HOST', SOURCE_PORT=$SRC_PORT,"
echo "      SOURCE_USER='$SRC_USER',"
echo "      SOURCE_LOG_FILE='$SRC_LOG_FILE', SOURCE_LOG_POS=$SRC_LOG_POS"
echo "    START REPLICA"
echo ""
printf "  Proceed? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "  Cancelled."; exit 0; fi

# ---- Apply ----
echo ""
mysql_q <<EOF
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$SRC_HOST',
  SOURCE_PORT=$SRC_PORT,
  SOURCE_USER='$SRC_USER',
  SOURCE_PASSWORD='$SRC_PASS',
  SOURCE_LOG_FILE='$SRC_LOG_FILE',
  SOURCE_LOG_POS=$SRC_LOG_POS;
START REPLICA;
EOF
REPL_EXIT=$?

if [ $REPL_EXIT -ne 0 ]; then
    echo "  ERROR: Replication setup failed (exit code $REPL_EXIT)"
    echo "  Run option 25 to inspect the error."
    exit 1
fi

# ---- Store password and save config ----
printf '%s' "$SRC_PASS" > "$REPL_PASS_FILE"
chmod 600 "$REPL_PASS_FILE"
sed -i "s|^REPL_SOURCE_HOST=.*|REPL_SOURCE_HOST=$SRC_HOST|" "$CONFIG_FILE"
sed -i "s|^REPL_SOURCE_USER=.*|REPL_SOURCE_USER=$SRC_USER|" "$CONFIG_FILE"
sed -i "s|^REPL_SOURCE_PORT=.*|REPL_SOURCE_PORT=$SRC_PORT|" "$CONFIG_FILE"

# ---- Show result ----
echo ""
echo "  Replication configured. Current status:"
echo ""
RAW=$(mysql_q -e "SHOW REPLICA STATUS\G" 2>/dev/null)
[ -z "$RAW" ] && RAW=$(mysql_q -e "SHOW SLAVE STATUS\G" 2>/dev/null)
echo "$RAW" | grep -E "Source_Host|Master_Host|Source_Log_File|Master_Log_File|Exec_.*Log_Pos|Read_.*Log_Pos|Replica_IO_Running|Slave_IO_Running|Replica_SQL_Running|Slave_SQL_Running|Seconds_Behind|Last_IO_Error|Last_SQL_Error" \
    | sed 's/^/    /'
