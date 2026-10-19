#!/bin/bash
# Menu 55: make this server the primary. Stops replication and forgets the source (RESET REPLICA ALL), so a MySQL
# restart or the old primary coming back can never replay changes onto it. Use on server02 when server01 is lost.
source "$HOME/.10mila_menu.conf"
echo "--- Stop replication: this server becomes the primary ---"
echo ""
printf "  MySQL user   [%s]: " "${DB_USER:-root}"
read -r input_user
DB_USER_IN="${input_user:-${DB_USER:-root}}"
printf "  MySQL password: "
read -rs DB_PASS
echo ""
mysql_q() { MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER_IN" "$@"; }
status="$(mysql_q -e 'SHOW REPLICA STATUS\G' 2>&1)" || { echo "  ERROR: $status"; exit 1; }
if [ -z "$status" ]; then echo "  This server does not replicate from anyone: it already is a primary."; exit 0; fi
echo "$status" | grep -E 'Source_Host|Source_Port|Replica_(IO|SQL)_Running:|Seconds_Behind_Source' | sed 's/^ */    /'
echo ""
echo "  After this, this server no longer follows its source. Make sure the source is really lost."
printf "  Type YES to stop replication: "
read -r confirm
[ "$confirm" = YES ] || { echo "  Cancelled."; exit 0; }
mysql_q -e 'STOP REPLICA; RESET REPLICA ALL;' || { echo "  ERROR: could not stop replication"; exit 1; }
[ -z "$(mysql_q -e 'SHOW REPLICA STATUS\G')" ] && echo "  Replication STOPPED: this server is the primary." || { echo "  ERROR: replication is still configured"; exit 1; }
