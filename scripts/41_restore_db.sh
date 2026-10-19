#!/bin/bash
# ============================================================
#  Restore database from a backup file
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Restore Database from Backup ---"
echo ""

# ---- Find backup files ----
SEARCH_DIR="${BACKUP_DIR:-$HOME/backups}"

mapfile -t BACKUPS < <(ls -t "$SEARCH_DIR"/*.sql 2>/dev/null)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo "  No .sql backup files found in: $SEARCH_DIR"
    echo ""
    printf "  Enter full path to backup file manually: "
    read -r BACKUP_FILE
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "  ERROR: File not found."
        exit 1
    fi
else
    # ---- List backups ----
    echo "  Backup directory: $SEARCH_DIR"
    echo ""
    printf "  %-4s  %-8s  %-20s  %s\n" "No." "Size" "Date/Time (UTC)" "Filename"
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
        echo "  ERROR: Invalid selection."
        exit 1
    fi

    BACKUP_FILE="${BACKUPS[$((sel-1))]}"
fi

echo ""
echo "  Selected: $(basename "$BACKUP_FILE")"
echo "  Size    : $(du -sh "$BACKUP_FILE" | cut -f1)"
echo ""

# ---- MySQL credentials ----
DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user   [%s]: " "$DEFAULT_DB_USER"
read -r input_user
DB_USER="${input_user:-$DEFAULT_DB_USER}"

printf "  MySQL password: "
read -rs DB_PASS
echo ""

# ---- Target database ----
DEFAULT_TARGET="${LAST_SOURCEDB}"
if [ -n "$DEFAULT_TARGET" ]; then
    printf "  Target database [%s]: " "$DEFAULT_TARGET"
else
    printf "  Target database: "
fi
read -r input_target
TARGET_DB="${input_target:-$DEFAULT_TARGET}"

if [ -z "$TARGET_DB" ]; then
    echo "  ERROR: No target database specified."
    exit 1
fi

echo ""

# ---- Check if target database already exists ----
DB_EXISTS=$(mysql -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES LIKE '$TARGET_DB';" 2>/dev/null | grep -c "$TARGET_DB" || true)

if [ "$DB_EXISTS" -gt 0 ]; then
    echo "  *** WARNING *** Database '$TARGET_DB' already exists."
    echo "  All existing data will be OVERWRITTEN and cannot be recovered."
    echo ""
    printf "  Type YES to confirm overwrite: "
    read -r confirm1
    if [ "$confirm1" != "YES" ]; then
        echo "  Cancelled."
        exit 0
    fi

    echo ""
    echo "  *** FINAL WARNING *** This is your last chance to abort."
    printf "  Type YES again to proceed with overwrite: "
    read -r confirm2
    if [ "$confirm2" != "YES" ]; then
        echo "  Cancelled."
        exit 0
    fi
else
    echo "  Database '$TARGET_DB' does not exist — it will be created."
    printf "  Proceed with restore? [Y/n]: "
    read -r confirm
    confirm="${confirm:-Y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "  Cancelled."
        exit 0
    fi

    # Create the database
    mysql -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE \`$TARGET_DB\`;" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "  ERROR: Could not create database '$TARGET_DB'."
        exit 1
    fi
fi

# ---- Stop ola10mila if running ----
SERVICE_WAS_RUNNING=false
if systemctl is-active --quiet ola10mila 2>/dev/null; then
    SERVICE_WAS_RUNNING=true
    echo "  Stopping ola10mila service before restore..."
    sudo systemctl stop ola10mila
    echo "  ola10mila stopped."
fi
echo ""

echo "  Restoring $(basename "$BACKUP_FILE") -> $TARGET_DB ..."
echo "  (this may take a while for large backups)"
echo ""

mysql -u "$DB_USER" -p"$DB_PASS" "$TARGET_DB" < "$BACKUP_FILE"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "  Restore SUCCESSFUL: '$TARGET_DB' restored from $(basename "$BACKUP_FILE")"
    sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" "$CONFIG_FILE"
else
    echo "  Restore FAILED (exit code $EXIT_CODE)"
    echo "  Check MySQL error output above."
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
