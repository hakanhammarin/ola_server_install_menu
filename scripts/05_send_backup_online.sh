#!/bin/bash
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Send Backup to Online Server ---"
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

# Online server settings
DEFAULT_HOST="${ONLINE_HOST:-10mila.duckdns.org}"
DEFAULT_USER="${ONLINE_USER:-ec2_user}"
DEFAULT_PATH="${ONLINE_PATH:-~/backups}"
DEFAULT_PEM="${PEM_FILE:-~/.ssh/10mila.pem}"

printf "  Online host  [%s]: " "$DEFAULT_HOST"
read -r input_host
ONL_HOST="${input_host:-$DEFAULT_HOST}"

printf "  Remote user  [%s]: " "$DEFAULT_USER"
read -r input_user
ONL_USER="${input_user:-$DEFAULT_USER}"

printf "  Remote path  [%s]: " "$DEFAULT_PATH"
read -r input_path
ONL_PATH="${input_path:-$DEFAULT_PATH}"

printf "  PEM key file [%s]: " "$DEFAULT_PEM"
read -r input_pem
ONL_PEM="${input_pem:-$DEFAULT_PEM}"
ONL_PEM="${ONL_PEM/#\~/$HOME}"   # expand ~ manually

if [ ! -f "$ONL_PEM" ]; then
    echo "ERROR: PEM file not found: $ONL_PEM"
    exit 1
fi

echo ""
echo "  From : $BACKUP_FILE"
echo "  To   : $ONL_USER@$ONL_HOST:$ONL_PATH"
echo "  Key  : $ONL_PEM"
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
scp -i "$ONL_PEM" "$BACKUP_FILE" "$ONL_USER@$ONL_HOST:$ONL_PATH"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "  Transfer SUCCESSFUL"
    sed -i "s|^ONLINE_HOST=.*|ONLINE_HOST=$ONL_HOST|" "$CONFIG_FILE"
    sed -i "s|^ONLINE_USER=.*|ONLINE_USER=$ONL_USER|" "$CONFIG_FILE"
    sed -i "s|^ONLINE_PATH=.*|ONLINE_PATH=$ONL_PATH|" "$CONFIG_FILE"
    sed -i "s|^PEM_FILE=.*|PEM_FILE=$ONL_PEM|" "$CONFIG_FILE"
    sed -i "s|^LAST_BACKUP_FILE=.*|LAST_BACKUP_FILE=$BACKUP_FILE|" "$CONFIG_FILE"
else
    echo "  Transfer FAILED (exit code $EXIT_CODE)"
fi
