#!/bin/bash
# Menu 43 and 45 on the console: the golden database is uploaded (43) and unlocked (45) on the web page only, behind
# the PIN. This shows what is there and whether the golden restore (44) is locked.
source "$HOME/.10mila_menu.conf"
DIR="${BACKUP_DIR:-$HOME/backups}"
echo "--- Golden database ---"
echo ""
echo "  Upload (43) and unlock (45) are on the web page: http://$(hostname -I | awk '{print $1}'):8096 (PIN)."
echo ""
ls -lh "$DIR"/*golden*.sql 2>/dev/null | sed 's/^/  /' || true
ls "$DIR"/*golden*.sql >/dev/null 2>&1 || echo "  No golden backup uploaded."
[ -e "$DIR/.golden.lock" ] && echo "  44 is LOCKED: restored $(cat "$DIR/.golden.lock")" || echo "  44 is unlocked."
