#!/bin/bash
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Send Backup to Secondary Server ---"
echo ""

# Determine backup file (sticky default)
if [ -n "$LAST_BACKUP_FILE" ] && [ -f "$LAST_BACKUP_FILE" ]; then
    printf "  Backup file [%s]: " "$LAST_BACKUP_FILE"
else
    printf "  Backup file: "
fi
read -r input_file
BACKUP_FILE="${input_file:-$LAST_BACKUP_FILE}"

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: File not found: $BACKUP_FILE"
    exit 1
fi

# Secondary server settings
DEFAULT_HOST="${SECONDARY_HOST}"
DEFAULT_USER="${SECONDARY_USER:-user}"
DEFAULT_PATH="${SECONDARY_PATH:-~/backups}"

printf "  Secondary host [%s]: " "$DEFAULT_HOST"
read -r input_host
SEC_HOST="${input_host:-$DEFAULT_HOST}"

printf "  Remote user   [%s]: " "$DEFAULT_USER"
read -r input_user
SEC_USER="${input_user:-$DEFAULT_USER}"

printf "  Remote path   [%s]: " "$DEFAULT_PATH"
read -r input_path
SEC_PATH="${input_path:-$DEFAULT_PATH}"

echo ""
echo "  From : $BACKUP_FILE"
echo "  To   : $SEC_USER@$SEC_HOST:$SEC_PATH"
echo ""
printf "  Proceed? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
fi

echo ""
echo "  Transferring..."
scp "$BACKUP_FILE" "$SEC_USER@$SEC_HOST:$SEC_PATH"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  Transfer SUCCESSFUL"
    sed -i "s|^SECONDARY_HOST=.*|SECONDARY_HOST=$SEC_HOST|" "$CONFIG_FILE"
    sed -i "s|^SECONDARY_USER=.*|SECONDARY_USER=$SEC_USER|" "$CONFIG_FILE"
    sed -i "s|^SECONDARY_PATH=.*|SECONDARY_PATH=$SEC_PATH|" "$CONFIG_FILE"
    sed -i "s|^LAST_BACKUP_FILE=.*|LAST_BACKUP_FILE=$BACKUP_FILE|" "$CONFIG_FILE"
else
    echo "  Transfer FAILED (exit code $EXIT_CODE)"
fi
