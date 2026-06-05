#!/bin/bash
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"

echo "--- Last Backup Info ---"
echo ""

if [ -z "$LAST_BACKUP_FILE" ]; then
    echo "  No backup has been created yet in this session."
else
    echo "  File : $LAST_BACKUP_FILE"
    if [ -f "$LAST_BACKUP_FILE" ]; then
        SIZE=$(du -sh "$LAST_BACKUP_FILE" | cut -f1)
        MOD=$(stat -c '%y' "$LAST_BACKUP_FILE" 2>/dev/null || stat -f '%Sm' "$LAST_BACKUP_FILE" 2>/dev/null)
        echo "  Size : $SIZE"
        echo "  Date : $MOD"
    else
        echo "  (file no longer exists at that path)"
    fi
fi

echo ""
echo "  Backup directory : ${BACKUP_DIR:-$HOME/backups}"
if [ -d "${BACKUP_DIR:-$HOME/backups}" ]; then
    echo ""
    echo "  Recent backups:"
    ls -lht "${BACKUP_DIR:-$HOME/backups}"/*.sql 2>/dev/null | head -10 || echo "  (none found)"
fi
