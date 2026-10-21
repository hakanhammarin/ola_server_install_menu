#!/bin/bash
# Menu 31-35: send the last backup to another server: server01, server02, server03, aws or util.
# Uses the backup key (BACKUP_KEY, made at deploy) as the upload-only account BACKUP_USER, into BACKUP_REMOTE_DIR.
# The other side lets that key do nothing but upload (SFTP), so this works without a password or the admin Mac.
# The file arrives as "<this server>__<name>" (a file that came from another server keeps that server's name): the
# receiver's housekeeping keeps the newest auto-backups per sender.
#   30_send_backup.sh <server01|server02|server03|aws|util> [file]
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"
case "$1" in
    server01) HOST="$SERVER01_HOST" ;; server02) HOST="$SERVER02_HOST" ;; server03) HOST="$SERVER03_HOST" ;;
    aws) HOST="$AWS_HOST" ;; util) HOST="$UTIL_HOST" ;;
    *) echo "usage: $0 server01|server02|server03|aws|util [file]"; exit 2 ;;
esac
KEY="${BACKUP_KEY:-$HOME/.ssh/10mila_backup}"; RUSER="${BACKUP_USER:-olabackup}"; RDIR="${BACKUP_REMOTE_DIR:-/srv/10mila-backups}"

echo "--- Send backup to $1 ---"
echo ""
[ -n "$HOST" ] || { echo "  ERROR: no address for $1 in the menu config (option 69)."; exit 1; }
if hostname -I 2>/dev/null | tr ' ' '\n' | grep -qxF "$HOST"; then echo "  ERROR: this is $1 itself."; exit 1; fi
[ -f "$KEY" ] || { echo "  ERROR: backup key $KEY is missing (made at deploy)."; exit 1; }

BACKUP_FILE="$2"
if [ -z "$BACKUP_FILE" ]; then
    printf "  Backup file [%s]: " "$LAST_BACKUP_FILE"
    read -r input_file
    BACKUP_FILE="${input_file:-$LAST_BACKUP_FILE}"
fi
[ -f "$BACKUP_FILE" ] || { echo "  ERROR: File not found: $BACKUP_FILE"; exit 1; }

RNAME="$(basename "$BACKUP_FILE")"
case "$RNAME" in *__*) ;; *) RNAME="$(hostname -s)__$RNAME" ;; esac   # a file passed on keeps its first sender's name
echo ""
echo "  From : $BACKUP_FILE"
echo "  To   : $1 ($RUSER@$HOST:$RDIR/$RNAME)"
echo ""
printf "  Proceed? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Cancelled."; exit 0; }

echo ""
echo "  Transferring..."
if scp -q -o BatchMode=yes -o ConnectTimeout=10 -i "$KEY" "$BACKUP_FILE" "$RUSER@$HOST:$RDIR/$RNAME"; then
    echo "  Transfer SUCCESSFUL"
else
    echo "  Transfer FAILED (exit code $?)"
    exit 1
fi
