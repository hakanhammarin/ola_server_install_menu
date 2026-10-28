#!/bin/bash
# Menu 44: the golden database, prepared offline, into the production database GOLDEN_DB (default tiomilaprod).
# The golden file is a backup whose name contains "golden" in the backup folder (uploaded with 43 on the web page).
# The database is dropped and created empty first, so nothing from before survives; replicas follow through
# replication. OLA is stopped during the restore and started again.
# After a good restore the golden file is deleted and the golden lock is set: 43 and 44 refuse until someone
# unlocks with 45 on the web page (PIN). A second golden restore during the event would wipe the race.
#   44_restore_golden.sh [file]
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE"
DIR="${BACKUP_DIR:-$HOME/backups}"
DB="${GOLDEN_DB:-tiomilaprod}"
LOCK="$DIR/.golden.lock"
echo "--- Restore the golden database into $DB ---"
echo ""
case "$DB" in *[!A-Za-z0-9_]*|"") echo "  ERROR: bad GOLDEN_DB '$DB' in the menu config"; exit 1 ;; esac
if [ -e "$LOCK" ]; then echo "  LOCKED: the golden database was already restored ($(cat "$LOCK")). Unlock with 45 on the web page (PIN)."; exit 1; fi

FILE="$1"
if [ -z "$FILE" ]; then
    mapfile -t G < <(ls -t "$DIR"/*golden*.sql 2>/dev/null)
    [ ${#G[@]} -gt 0 ] || { echo "  No golden backup (*golden*.sql) in $DIR. Upload it with 43 on the web page."; exit 1; }
    for i in "${!G[@]}"; do printf "  %-4s  %-8s  %s\n" "$((i+1))" "$(du -sh "${G[$i]}" | cut -f1)" "$(basename "${G[$i]}")"; done
    printf "  Select golden backup [1-%d]: " "${#G[@]}"
    read -r sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#G[@]}" ] || { echo "  ERROR: Invalid selection."; exit 1; }
    FILE="${G[$((sel-1))]}"
fi
[ -s "$FILE" ] || { echo "  ERROR: File not found or empty: $FILE"; exit 1; }
# A golden backup must restore into any name: refuse one that switches database itself.
if grep -qiE '^(USE |CREATE DATABASE)' "$FILE"; then echo "  ERROR: $(basename "$FILE") selects its own database (USE / CREATE DATABASE): make it without --databases."; exit 1; fi

printf "  MySQL user   [%s]: " "${DB_USER:-root}"
read -r input_user
DB_USER_IN="${input_user:-${DB_USER:-root}}"
printf "  MySQL password: "
read -rs DB_PASS
echo ""
mysql_q() { MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER_IN" "$@"; }
mysql_q -e 'select 1' >/dev/null || { echo "  ERROR: cannot log in to MySQL"; exit 1; }

echo ""
echo "  File     : $(basename "$FILE") ($(du -sh "$FILE" | cut -f1))"
echo "  Database : $DB  (dropped and created empty first)"
echo ""
printf "  Type YES to replace %s with the golden database: " "$DB"
read -r confirm
[ "$confirm" = YES ] || { echo "  Cancelled."; exit 0; }

WAS_RUNNING=false
systemctl is-active --quiet ola10mila && { WAS_RUNNING=true; sudo systemctl stop ola10mila; echo "  ola10mila stopped."; }
mysql_q -e "DROP DATABASE IF EXISTS \`$DB\`; CREATE DATABASE \`$DB\`;" && mysql_q "$DB" < "$FILE"
rc=$?
if [ $rc -eq 0 ]; then
    echo "  Golden restore SUCCESSFUL: $DB from $(basename "$FILE")"
    # Other services put idempotent SQL for their own tables and grants here (teamchanges: zz_teamchanges); a restored
    # database does not have them, so they are applied right after every restore.
    for h in "${AFTER_RESTORE_DIR:-/etc/10mila-menu/after-restore.d}"/*.sql; do
        [ -f "$h" ] || continue
        if mysql_q "$DB" < "$h"; then echo "  after restore: $(basename "$h") applied"; else echo "  after restore: $(basename "$h") FAILED"; rc=1; fi
    done
    sed -i "s|^LAST_SOURCEDB=.*|LAST_SOURCEDB=$DB|" "$CONFIG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M') from $(basename "$FILE")" > "$LOCK" && chmod 660 "$LOCK"
    rm -f "$FILE"
    echo "  Golden file deleted and golden restore LOCKED (unlock: 45 on the web page)."
else
    echo "  Golden restore FAILED (exit code $rc)"
fi
$WAS_RUNNING && { sudo systemctl start ola10mila; echo "  ola10mila started."; }
exit $rc
