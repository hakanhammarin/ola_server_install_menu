#!/bin/bash
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Database Backup ---"
echo ""

# Prompt for source database (sticky default)
if [ -n "$LAST_SOURCEDB" ]; then
    printf "  Source database [%s]: " "$LAST_SOURCEDB"
else
    printf "  Source database: "
fi
read -r input_db
SOURCEDB="${input_db:-$LAST_SOURCEDB}"

if [ -z "$SOURCEDB" ]; then
    echo "ERROR: No database specified."
    exit 1
fi

# Prompt for MySQL user (sticky default)
DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user       [%s]: " "$DEFAULT_DB_USER"
read -r input_db_user
DB_USER="${input_db_user:-$DEFAULT_DB_USER}"

# Always prompt for password (never stored)
printf "  MySQL password: "
read -rs DB_PASS
echo ""

# Prompt for backup directory (sticky default)
DEFAULT_BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
printf "  Backup directory [%s]: " "$DEFAULT_BACKUP_DIR"
read -r input_dir
BACKUP_DIR="${input_dir:-$DEFAULT_BACKUP_DIR}"

mkdir -p "$BACKUP_DIR"

# Generate ISO-8601 timestamp filename
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
BACKUP_FILE="$BACKUP_DIR/${SOURCEDB}_${TIMESTAMP}.sql"

echo ""
echo "  Database : $SOURCEDB"
echo "  User     : $DB_USER"
echo "  File     : $BACKUP_FILE"
echo ""
printf "  Proceed? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
fi

echo ""
echo "  Running mysqldump..."
mysqldump --source-data=2 -u "$DB_USER" -p"$DB_PASS" "$SOURCEDB" > "$BACKUP_FILE"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "  Backup SUCCESSFUL: $BACKUP_FILE ($SIZE)"

    # Save sticky values to config (password is never saved)
    sed -i "s|^LAST_SOURCEDB=.*|LAST_SOURCEDB=$SOURCEDB|" "$CONFIG_FILE"
    sed -i "s|^LAST_BACKUP_FILE=.*|LAST_BACKUP_FILE=$BACKUP_FILE|" "$CONFIG_FILE"
    sed -i "s|^BACKUP_DIR=.*|BACKUP_DIR=$BACKUP_DIR|" "$CONFIG_FILE"
    sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" "$CONFIG_FILE"
else
    echo "  Backup FAILED (exit code $EXIT_CODE)"
    rm -f "$BACKUP_FILE"
fi
