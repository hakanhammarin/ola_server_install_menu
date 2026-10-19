#!/bin/bash
# ============================================================
#  10mila Auto-Backup Runner
#  Called by systemd 10mila-autobackup.service every 15 min.
#  Credentials read from ~/.10mila_autobackup.cnf (chmod 600)
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
CRED_FILE="$HOME/.10mila_autobackup.cnf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config not found: $CONFIG_FILE"
    exit 1
fi

if [ ! -f "$CRED_FILE" ]; then
    echo "ERROR: Credentials file not found: $CRED_FILE"
    exit 1
fi

source "$CONFIG_FILE"

SOURCEDB="${LAST_SOURCEDB}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"

if [ -z "$SOURCEDB" ]; then
    echo "ERROR: LAST_SOURCEDB is not set in $CONFIG_FILE"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
BACKUP_FILE="$BACKUP_DIR/${SOURCEDB}_auto_${TIMESTAMP}.sql"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Starting auto-backup: $SOURCEDB -> $BACKUP_FILE"

mysqldump --defaults-file="$CRED_FILE" --source-data=2 "$SOURCEDB" > "$BACKUP_FILE"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Auto-backup OK: $BACKUP_FILE ($SIZE)"

    # Update last backup reference in config
    sed -i "s|^LAST_BACKUP_FILE=.*|LAST_BACKUP_FILE=$BACKUP_FILE|" "$CONFIG_FILE"

    # Rotate: keep only the 96 most recent auto backups (24h worth at 15min intervals)
    ls -t "$BACKUP_DIR"/${SOURCEDB}_auto_*.sql 2>/dev/null | tail -n +97 | xargs -r rm --
    KEPT=$(ls "$BACKUP_DIR"/${SOURCEDB}_auto_*.sql 2>/dev/null | wc -l)
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Rotation: $KEPT auto-backups retained"
else
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Auto-backup FAILED (exit code $EXIT_CODE)"
    rm -f "$BACKUP_FILE"
    exit $EXIT_CODE
fi
