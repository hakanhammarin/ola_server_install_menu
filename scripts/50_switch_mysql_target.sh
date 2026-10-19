#!/bin/bash
# Menu 51-54: switch the MySQL server that OLA on this machine uses: "local" (127.0.0.1:3306), "server01"
# (PRIMARY_HOST:PRIMARY_PORT), "server02" (SECONDARY_DB_HOST:SECONDARY_DB_PORT) or "server03"
# (TERTIARY_DB_HOST:TERTIARY_DB_PORT) from ~/.10mila_menu.conf.
# On the AWS OLA server the arena servers are their reverse tunnels (127.0.0.1:33306, :33307, ...).
# Only the address in ola.properties changes; the OLA database account must exist with the same password
# on every server (it does when it is created on server01 and replicated).
#   50_switch_mysql_target.sh                                      show the current target and ask
#   50_switch_mysql_target.sh local|server01|server02|server03     switch without asking (menu 51-54)
#   50_switch_mysql_target.sh status                               print the current target only
source "$HOME/.10mila_menu.conf" 2>/dev/null
PRIMARY_HOST="${PRIMARY_HOST:-192.168.1.21}"
PRIMARY_PORT="${PRIMARY_PORT:-3306}"
SECONDARY_DB_HOST="${SECONDARY_DB_HOST:-$SECONDARY_HOST}"
SECONDARY_DB_PORT="${SECONDARY_DB_PORT:-3306}"
TERTIARY_DB_HOST="${TERTIARY_DB_HOST:-}"
TERTIARY_DB_PORT="${TERTIARY_DB_PORT:-3306}"
PROPS="${OLA_PROPERTIES:-/opt/OLA_6/OLA6/ola.properties}"

# ola.properties holds e.g. MYSQL_DSN_PREFIX=127.0.0.1\:3306/
dsn="$(sed -n 's/^MYSQL_DSN_PREFIX=//p' "$PROPS" 2>/dev/null | tail -1 | tr -d '\\')"
dsn="${dsn%%/*}"
case "$dsn" in
    127.0.0.1:3306|localhost:3306)            current=local ;;
    "$PRIMARY_HOST:$PRIMARY_PORT")            current=server01 ;;
    "$SECONDARY_DB_HOST:$SECONDARY_DB_PORT")  current=server02 ;;
    "$TERTIARY_DB_HOST:$TERTIARY_DB_PORT")    current=server03 ;;
    *)                                        current="${dsn:-unknown}" ;;
esac
[ "$1" = status ] && { echo "$current"; exit 0; }

echo "--- OLA database target ---"
echo ""
echo "  Current: $current ($dsn)"
echo "  local    = MySQL on this server (127.0.0.1:3306)"
echo "  server01 = $PRIMARY_HOST:$PRIMARY_PORT (PRIMARY_HOST/PRIMARY_PORT in the menu config, option 69)"
echo "  server02 = $SECONDARY_DB_HOST:$SECONDARY_DB_PORT (SECONDARY_DB_HOST/SECONDARY_DB_PORT)"
echo "  server03 = ${TERTIARY_DB_HOST:-not set}:$TERTIARY_DB_PORT (TERTIARY_DB_HOST/TERTIARY_DB_PORT)"
echo ""
target="$1"
if [ -z "$target" ]; then
    printf "  Switch to (local/server01/server02/server03, Enter = no change) and restart OLA: "
    read -r target
    [ -n "$target" ] || { echo "  Nothing changed."; exit 0; }
fi
case "$target" in
    local)    new=127.0.0.1;           port=3306 ;;
    server01) new="$PRIMARY_HOST";      port="$PRIMARY_PORT" ;;
    server02) new="$SECONDARY_DB_HOST"; port="$SECONDARY_DB_PORT" ;;
    server03) new="$TERTIARY_DB_HOST";  port="$TERTIARY_DB_PORT" ;;
    *) echo "usage: $0 [local|server01|server02|server03|status]"; exit 2 ;;
esac
case "$new" in *[!A-Za-z0-9.-]*|"") echo "ERROR: bad address '$new' for $target in the menu config"; exit 1 ;; esac
case "$port" in *[!0-9]*|"") echo "ERROR: bad port '$port' for $target in the menu config"; exit 1 ;; esac

# Never point OLA at a MySQL that does not answer.
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$new/$port" 2>/dev/null; then
    echo "ERROR: no MySQL answers on $new:$port. Nothing changed."
    exit 1
fi

sudo sed -i "s|^MYSQL_DSN_PREFIX=.*|MYSQL_DSN_PREFIX=$new\\\\:$port/|" "$PROPS" || { echo "ERROR: could not edit $PROPS"; exit 1; }
grep -q "^MYSQL_DSN_PREFIX=$new\\\\:$port/" "$PROPS" || { echo "ERROR: MYSQL_DSN_PREFIX not found in $PROPS"; exit 1; }
echo "  OLA now uses $target ($new:$port)."
if systemctl is-active --quiet ola10mila; then
    sudo systemctl stop ola10mila
    sudo systemctl start ola10mila
    echo "  ola10mila restarted."
else
    echo "  ola10mila is not running: start it with option 11."
fi
