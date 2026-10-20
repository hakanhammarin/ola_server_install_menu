#!/bin/bash
# ============================================================
#  Restore database and start MySQL replication
#  1. Restore from backup (same as option 41)
#  2. Extract binlog position from backup file (CHANGE MASTER TO comment)
#  3. Prompt for replication source settings (sticky)
#  4. Configure and start replica
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
REPL_PASS_FILE="$HOME/.10mila_repl.pass"

source "$CONFIG_FILE"

# ---- Ensure replication config keys exist ----
grep -q "^REPL_SOURCE_HOST=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_HOST=" >> "$CONFIG_FILE"
grep -q "^REPL_SOURCE_USER=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_USER=repl" >> "$CONFIG_FILE"
grep -q "^REPL_SOURCE_PORT=" "$CONFIG_FILE" 2>/dev/null || echo "REPL_SOURCE_PORT=3306" >> "$CONFIG_FILE"
source "$CONFIG_FILE"

echo "--- Restore Database and Start Replication ---"
echo ""

# ============================================================
# STEP 1 — SELECT BACKUP FILE
# ============================================================
SEARCH_DIR="${BACKUP_DIR:-$HOME/backups}"

mapfile -t BACKUPS < <(ls -t "$SEARCH_DIR"/*.sql 2>/dev/null)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo "  No .sql backup files found in: $SEARCH_DIR"
    echo ""
    printf "  Enter full path to backup file manually: "
    read -r BACKUP_FILE
    if [ ! -f "$BACKUP_FILE" ]; then echo "  ERROR: File not found."; exit 1; fi
else
    echo "  Backup directory: $SEARCH_DIR"
    echo ""
    printf "  %-4s  %-8s  %-20s  %s\n" "No." "Size" "Date/Time" "Filename"
    echo "  -----------------------------------------------------------------------"
    for i in "${!BACKUPS[@]}"; do
        FILE="${BACKUPS[$i]}"
        FNAME=$(basename "$FILE")
        FSIZE=$(du -sh "$FILE" 2>/dev/null | cut -f1)
        FDATE=$(stat -c '%y' "$FILE" 2>/dev/null | cut -c1-19)
        printf "  %-4s  %-8s  %-20s  %s\n" "$((i+1))" "$FSIZE" "$FDATE" "$FNAME"
    done
    echo ""
    printf "  Select backup number [1-%d]: " "${#BACKUPS[@]}"
    read -r sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#BACKUPS[@]}" ]; then
        echo "  ERROR: Invalid selection."; exit 1
    fi
    BACKUP_FILE="${BACKUPS[$((sel-1))]}"
fi

echo ""
echo "  Selected: $(basename "$BACKUP_FILE")"
echo "  Size    : $(du -sh "$BACKUP_FILE" | cut -f1)"

# ============================================================
# STEP 2 — EXTRACT BINLOG POSITION FROM BACKUP FILE
# ============================================================
echo ""
echo "--- Step 2: Detecting binlog position from backup file ---"

MASTER_LINE=$(grep "CHANGE MASTER TO" "$BACKUP_FILE" 2>/dev/null | head -1)
AUTO_LOG_FILE=""
AUTO_LOG_POS=""

if [ -n "$MASTER_LINE" ]; then
    echo "  Found: $MASTER_LINE"
    AUTO_LOG_FILE=$(echo "$MASTER_LINE" | sed -n "s/.*MASTER_LOG_FILE='\([^']*\)'.*/\1/p")
    AUTO_LOG_POS=$(echo "$MASTER_LINE"  | sed -n "s/.*MASTER_LOG_POS=\([0-9]*\).*/\1/p")
    [ -n "$AUTO_LOG_FILE" ] && echo "  Detected log file: $AUTO_LOG_FILE"
    [ -n "$AUTO_LOG_POS"  ] && echo "  Detected log pos : $AUTO_LOG_POS"
else
    echo "  No CHANGE MASTER TO line found — you will enter binlog position manually."
fi

# ============================================================
# STEP 3 — MYSQL CREDENTIALS + TARGET DB
# ============================================================
echo ""
echo "--- Step 3: MySQL credentials ---"

DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user   [%s]: " "$DEFAULT_DB_USER"
read -r input_user
DB_USER_IN="${input_user:-$DEFAULT_DB_USER}"

printf "  MySQL password: "
read -rs DB_PASS
echo ""

DEFAULT_TARGET="${LAST_SOURCEDB}"
if [ -n "$DEFAULT_TARGET" ]; then
    printf "  Target database [%s]: " "$DEFAULT_TARGET"
else
    printf "  Target database: "
fi
read -r input_target
TARGET_DB="${input_target:-$DEFAULT_TARGET}"

if [ -z "$TARGET_DB" ]; then echo "  ERROR: No target database specified."; exit 1; fi

# ============================================================
# STEP 4 — REPLICATION SOURCE PROMPTS
# ============================================================
echo ""
echo "--- Step 4: Replication source settings ---"

DEFAULT_SRC_HOST="${REPL_SOURCE_HOST:-192.168.1.21}"
printf "  SOURCE_HOST  [%s]: " "$DEFAULT_SRC_HOST"
read -r input_src_host
SRC_HOST="${input_src_host:-$DEFAULT_SRC_HOST}"

DEFAULT_SRC_USER="${REPL_SOURCE_USER:-repl}"
printf "  SOURCE_USER  [%s]: " "$DEFAULT_SRC_USER"
read -r input_src_user
SRC_USER="${input_src_user:-$DEFAULT_SRC_USER}"

DEFAULT_SRC_PORT="${REPL_SOURCE_PORT:-3306}"
printf "  SOURCE_PORT  [%s]: " "$DEFAULT_SRC_PORT"
read -r input_src_port
SRC_PORT="${input_src_port:-$DEFAULT_SRC_PORT}"

DEFAULT_LOG_FILE="${AUTO_LOG_FILE}"
if [ -n "$DEFAULT_LOG_FILE" ]; then
    printf "  SOURCE_LOG_FILE  [%s]: " "$DEFAULT_LOG_FILE"
else
    printf "  SOURCE_LOG_FILE: "
fi
read -r input_log_file
SRC_LOG_FILE="${input_log_file:-$DEFAULT_LOG_FILE}"
if [ -z "$SRC_LOG_FILE" ]; then echo "  ERROR: SOURCE_LOG_FILE required."; exit 1; fi

DEFAULT_LOG_POS="${AUTO_LOG_POS}"
if [ -n "$DEFAULT_LOG_POS" ]; then
    printf "  SOURCE_LOG_POS  [%s]: " "$DEFAULT_LOG_POS"
else
    printf "  SOURCE_LOG_POS: "
fi
read -r input_log_pos
SRC_LOG_POS="${input_log_pos:-$DEFAULT_LOG_POS}"
if [ -z "$SRC_LOG_POS" ]; then echo "  ERROR: SOURCE_LOG_POS required."; exit 1; fi

# ---- Replication user password ----
if [ -f "$REPL_PASS_FILE" ]; then
    printf "  SOURCE_PASSWORD [stored, press Enter to reuse or type new]: "
    read -rs input_repl_pass
    echo ""
    if [ -n "$input_repl_pass" ]; then
        SRC_PASS="$input_repl_pass"
    else
        SRC_PASS="$(cat "$REPL_PASS_FILE")"
    fi
else
    printf "  SOURCE_PASSWORD: "
    read -rs SRC_PASS
    echo ""
fi

# ============================================================
# STEP 5 — CONFIRM AND RESTORE
# ============================================================
echo ""
echo "  =============================="
echo "  Restore plan:"
echo "    File   : $(basename "$BACKUP_FILE")"
echo "    DB     : $TARGET_DB"
echo "  Replication:"
echo "    Source : $SRC_USER@$SRC_HOST:$SRC_PORT"
echo "    Binlog : $SRC_LOG_FILE @ pos $SRC_LOG_POS"
echo "  =============================="
echo ""

DB_EXISTS=$(mysql -u "$DB_USER_IN" -p"$DB_PASS" -e "SHOW DATABASES LIKE '$TARGET_DB';" 2>/dev/null | grep -c "$TARGET_DB" || true)

if [ "$DB_EXISTS" -gt 0 ]; then
    echo "  *** WARNING *** Database '$TARGET_DB' already exists and will be OVERWRITTEN."
    printf "  Type YES to confirm: "
    read -r confirm1
    if [ "$confirm1" != "YES" ]; then echo "  Cancelled."; exit 0; fi
    printf "  Type YES again (final confirmation): "
    read -r confirm2
    if [ "$confirm2" != "YES" ]; then echo "  Cancelled."; exit 0; fi
else
    echo "  Database '$TARGET_DB' will be created."
    printf "  Proceed? [Y/n]: "
    read -r confirm
    confirm="${confirm:-Y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "  Cancelled."; exit 0; fi
    mysql -u "$DB_USER_IN" -p"$DB_PASS" -e "CREATE DATABASE \`$TARGET_DB\`;" 2>/dev/null
    [ $? -ne 0 ] && echo "  ERROR: Could not create database." && exit 1
fi

# ---- Stop ola10mila if running ----
SERVICE_WAS_RUNNING=false
if systemctl is-active --quiet ola10mila 2>/dev/null; then
    SERVICE_WAS_RUNNING=true
    echo "  Stopping ola10mila before restore..."
    sudo systemctl stop ola10mila
fi

# A replica that still replicates would keep applying its old source's changes into the tables being restored,
# and the new replication would then apply them a second time (duplicate key). Stop it first.
mysql -u "$DB_USER_IN" -p"$DB_PASS" -e "STOP REPLICA" 2>/dev/null
echo ""
echo "  Restoring $(basename "$BACKUP_FILE") -> $TARGET_DB ..."
echo "  (this may take a while)"
echo ""

mysql -u "$DB_USER_IN" -p"$DB_PASS" "$TARGET_DB" < "$BACKUP_FILE"
RESTORE_EXIT=$?

echo ""
if [ $RESTORE_EXIT -ne 0 ]; then
    echo "  Restore FAILED (exit code $RESTORE_EXIT)"
    echo "  Replication setup skipped."
    [ "$SERVICE_WAS_RUNNING" = true ] && sudo systemctl start ola10mila
    exit 1
fi
echo "  Restore SUCCESSFUL."

# ============================================================
# STEP 6 — CONFIGURE AND START REPLICATION
# ============================================================
echo ""
echo "--- Step 6: Configuring replication ---"

# The replication heartbeat (replicate.sh) writes one row into replmon on the source every minute. The dump holds
# only the OLA database, so a fresh standby needs that table before replication starts, or the first heartbeat stops it.
REPL_SQL=$(cat <<EOF
STOP REPLICA;
RESET REPLICA ALL;
CREATE DATABASE IF NOT EXISTS replmon;
CREATE TABLE IF NOT EXISTS replmon.replicamonitoring (k VARCHAR(32) PRIMARY KEY, v DATETIME(3) NOT NULL);
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$SRC_HOST',
  SOURCE_PORT=$SRC_PORT,
  SOURCE_USER='$SRC_USER',
  SOURCE_PASSWORD='$SRC_PASS',
  GET_SOURCE_PUBLIC_KEY=1,
  SOURCE_LOG_FILE='$SRC_LOG_FILE',
  SOURCE_LOG_POS=$SRC_LOG_POS;
START REPLICA;
EOF
)

echo "$REPL_SQL" | mysql -u "$DB_USER_IN" -p"$DB_PASS" 2>&1
REPL_EXIT=$?

if [ $REPL_EXIT -ne 0 ]; then
    echo ""
    echo "  ERROR: Replication setup failed (exit code $REPL_EXIT)"
    echo "  Check the output above. You can also run option 62 to debug."
else
    # ---- Store replication password securely ----
    printf '%s' "$SRC_PASS" > "$REPL_PASS_FILE"
    chmod 600 "$REPL_PASS_FILE"

    # ---- Save sticky config ----
    sed -i "s|^REPL_SOURCE_HOST=.*|REPL_SOURCE_HOST=$SRC_HOST|" "$CONFIG_FILE"
    sed -i "s|^REPL_SOURCE_USER=.*|REPL_SOURCE_USER=$SRC_USER|" "$CONFIG_FILE"
    sed -i "s|^REPL_SOURCE_PORT=.*|REPL_SOURCE_PORT=$SRC_PORT|" "$CONFIG_FILE"
    sed -i "s|^DB_USER=.*|DB_USER=$DB_USER_IN|" "$CONFIG_FILE"

    echo ""
    echo "  Replication configured and started."
    echo ""
    echo "  Quick status check:"
    mysql -u "$DB_USER_IN" -p"$DB_PASS" -e "SHOW REPLICA STATUS\G" 2>/dev/null \
        | grep -E "Slave_IO_Running|Slave_SQL_Running|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind|Last_Error|Running|Master_Log|Exec_Master|Source_Log|Exec_Source" \
        | sed 's/^/    /'
fi

# ---- Restart ola10mila if it was running before ----
if [ "$SERVICE_WAS_RUNNING" = true ]; then
    echo ""
    echo "  Starting ola10mila service..."
    sudo systemctl start ola10mila
    sleep 2
    if systemctl is-active --quiet ola10mila; then
        echo "  ola10mila is RUNNING"
    else
        echo "  WARNING: ola10mila did not start — check: journalctl -u ola10mila"
    fi
fi
