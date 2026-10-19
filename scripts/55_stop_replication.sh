#!/bin/bash
# Menu 55: make this server the primary. Stops replication and forgets the source (RESET REPLICA ALL), so a MySQL
# restart or the old primary coming back can never replay changes onto it. Use on server02 when server01 is lost.
# A primary must also have the replication account its standbys log in with: it is created here (the account on
# the old primary never reached the replicas, the dumps hold only the OLA database).
source "$HOME/.10mila_menu.conf"
REPL_PASS_FILE="$HOME/.10mila_repl.pass"
REPL_USER="${REPL_SOURCE_USER:-repl}"
echo "--- Stop replication: this server becomes the primary ---"
echo ""
printf "  MySQL user   [%s]: " "${DB_USER:-root}"
read -r input_user
DB_USER_IN="${input_user:-${DB_USER:-root}}"
printf "  MySQL password: "
read -rs DB_PASS
echo ""
printf "  Password of the replication account %s (Enter = the stored one): " "$REPL_USER"
read -rs REPL_PASS
echo ""
[ -n "$REPL_PASS" ] || REPL_PASS="$(cat "$REPL_PASS_FILE" 2>/dev/null)"
mysql_q() { MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER_IN" "$@"; }
repl_account() {
    [ -n "$REPL_PASS" ] || { echo "  WARNING: no replication password: standbys cannot replicate from this server yet."; return 0; }
    case "$REPL_USER$REPL_PASS" in *\'*|*\\*) echo "  ERROR: quote or backslash in the replication account"; return 1 ;; esac
    mysql_q <<SQL || { echo "  ERROR: could not create the replication account"; return 1; }
CREATE USER IF NOT EXISTS '$REPL_USER'@'%' IDENTIFIED BY '$REPL_PASS';
ALTER USER '$REPL_USER'@'%' IDENTIFIED BY '$REPL_PASS';
GRANT REPLICATION SLAVE ON *.* TO '$REPL_USER'@'%';
SQL
    printf '%s' "$REPL_PASS" > "$REPL_PASS_FILE"; chmod 600 "$REPL_PASS_FILE"
    echo "  Replication account $REPL_USER ready for the standbys."
}
status="$(mysql_q -e 'SHOW REPLICA STATUS\G' 2>&1)" || { echo "  ERROR: $status"; exit 1; }
if [ -z "$status" ]; then echo "  This server does not replicate from anyone: it already is a primary."; repl_account; exit $?; fi
echo "$status" | grep -E 'Source_Host|Source_Port|Replica_(IO|SQL)_Running:|Seconds_Behind_Source' | sed 's/^ */    /'
echo ""
echo "  After this, this server no longer follows its source. Make sure the source is really lost."
printf "  Type YES to stop replication: "
read -r confirm
[ "$confirm" = YES ] || { echo "  Cancelled."; exit 0; }
mysql_q -e 'STOP REPLICA; RESET REPLICA ALL;' || { echo "  ERROR: could not stop replication"; exit 1; }
[ -z "$(mysql_q -e 'SHOW REPLICA STATUS\G')" ] && echo "  Replication STOPPED: this server is the primary." || { echo "  ERROR: replication is still configured"; exit 1; }
repl_account
