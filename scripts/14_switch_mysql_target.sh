#!/bin/bash
# Switch the MySQL server that OLA on this machine uses: "local" (this server) or "server01"
# (PRIMARY_HOST in ~/.10mila_menu.conf). Only the address in ola.properties changes; the OLA
# database account must exist with the same password on both servers (it does when it is
# created on server01 and replicated).
#   14_switch_mysql_target.sh                    show the current target and ask
#   14_switch_mysql_target.sh local|server01     switch without asking
#   14_switch_mysql_target.sh status             print the current target only
source "$HOME/.10mila_menu.conf" 2>/dev/null
PRIMARY_HOST="${PRIMARY_HOST:-192.168.1.21}"
PROPS="${OLA_PROPERTIES:-/opt/OLA_6/OLA6/ola.properties}"

# ola.properties holds e.g. MYSQL_DSN_PREFIX=127.0.0.1\:3306/
host="$(sed -n 's/^MYSQL_DSN_PREFIX=\([^\\:]*\).*/\1/p' "$PROPS" 2>/dev/null | tail -1)"
case "$host" in
    127.0.0.1|localhost) current=local ;;
    "$PRIMARY_HOST")     current=server01 ;;
    *)                   current="${host:-unknown}" ;;
esac
[ "$1" = status ] && { echo "$current"; exit 0; }

echo "--- OLA database target ---"
echo ""
echo "  Current: $current ($host)"
echo "  local    = MySQL on this server (127.0.0.1)"
echo "  server01 = MySQL on $PRIMARY_HOST (PRIMARY_HOST in the menu config, option 24)"
echo ""
target="$1"
if [ -z "$target" ]; then
    [ "$current" = local ] && target=server01 || target=local
    printf "  Switch to %s and restart OLA? [y/N]: " "$target"
    read -r answer
    [ "$answer" = y ] || [ "$answer" = Y ] || { echo "  Nothing changed."; exit 0; }
fi
case "$target" in
    local)    new=127.0.0.1 ;;
    server01) new="$PRIMARY_HOST" ;;
    *) echo "usage: $0 [local|server01|status]"; exit 2 ;;
esac
case "$new" in *[!A-Za-z0-9.-]*|"") echo "ERROR: bad PRIMARY_HOST '$new' in the menu config"; exit 1 ;; esac

# Never point OLA at a MySQL that does not answer.
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$new/3306" 2>/dev/null; then
    echo "ERROR: no MySQL answers on $new:3306. Nothing changed."
    exit 1
fi

sudo sed -i "s|^MYSQL_DSN_PREFIX=.*|MYSQL_DSN_PREFIX=$new\\\\:3306/|" "$PROPS" || { echo "ERROR: could not edit $PROPS"; exit 1; }
grep -q "^MYSQL_DSN_PREFIX=$new" "$PROPS" || { echo "ERROR: MYSQL_DSN_PREFIX not found in $PROPS"; exit 1; }
echo "  OLA now uses $target ($new)."
if systemctl is-active --quiet ola10mila; then
    sudo systemctl stop ola10mila
    sudo systemctl start ola10mila
    echo "  ola10mila restarted."
else
    echo "  ola10mila is not running: start it with option 1."
fi
