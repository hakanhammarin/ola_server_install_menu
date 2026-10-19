#!/bin/bash
# Called by 10mila-autopush.timer (menu 36): every backup not sent yet goes to each of AUTOPUSH_TARGETS
# (default util) with 30_send_backup.sh. What was sent is kept in ~/.10mila_autopush_<target>.sent.
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
rc=0
for t in ${AUTOPUSH_TARGETS:-util}; do
    sent="$HOME/.10mila_autopush_$t.sent"; touch "$sent"
    # only files older than a minute: a backup being written is never sent half done
    for f in $(find "${BACKUP_DIR:-$HOME/backups}" -maxdepth 1 -name '*.sql' -mmin +1 -printf '%f\n' | sort); do
        grep -qxF "$f" "$sent" && continue
        if echo Y | bash "$DIR/30_send_backup.sh" "$t" "${BACKUP_DIR:-$HOME/backups}/$f" >/dev/null; then
            echo "$f" >> "$sent"; log "sent $f to $t"
        else log "FAILED to send $f to $t"; rc=1; fi
    done
done
exit $rc
