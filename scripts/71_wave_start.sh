#!/bin/bash
# Menu 71 (Herrkavlen) and 72 (Damkavlen): the wave start ("vågstart") of a chase leg. Every runner on the chase leg
# who has no start time after OLA's chase start draw (lottning), and has not started, gets the wave start time as
# allocated start time and start time. The organizer's SQL from 2024, with the class found by name and leg instead
# of a fixed eventClassId (ids differ between years).
# Run it on the server whose MySQL is the primary (server01, or the server that ran 55): a replica refuses, because a
# write there would break its replication. It is safe to run again: a runner who already has a start time is kept.
#   71_wave_start.sh herr|dam [time]     time HH:MM[:SS] or YYYY-MM-DD HH:MM[:SS]; empty = asked, default below
# Default wave time: the chase leg's first start (raceclasses.firstStartTime) + the class's wave limit
# (maxAfterForChaseStart, 1/100 s), the same cap OLA's draw uses. Class names and legs: CHASE_HERR / CHASE_DAM in the
# menu config ("Herrkavlen:4", "Damkavlen:3").
CONFIG_FILE="$HOME/.10mila_menu.conf"
source "$CONFIG_FILE" 2>/dev/null
DB="${GOLDEN_DB:-tiomilaprod}"
case "$1" in
    herr) spec="${CHASE_HERR:-Herrkavlen:4}" ;;
    dam)  spec="${CHASE_DAM:-Damkavlen:3}" ;;
    *) echo "usage: $0 herr|dam [time]"; exit 2 ;;
esac
CLASS="${spec%:*}" LEG="${spec##*:}"
WANT="$2"
echo "--- Wave start: $CLASS leg $LEG ---"
echo ""
case "$DB" in *[!A-Za-z0-9_]*|"") echo "  ERROR: bad GOLDEN_DB '$DB' in the menu config"; exit 1 ;; esac
case "$CLASS" in *[!A-Za-z0-9\ _-]*|"") echo "  ERROR: bad class name '$CLASS' in the menu config"; exit 1 ;; esac
case "$LEG" in *[!0-9]*|"") echo "  ERROR: bad leg '$LEG' in the menu config"; exit 1 ;; esac

printf "  MySQL user   [%s]: " "${DB_USER:-root}"
read -r input_user
DB_USER_IN="${input_user:-${DB_USER:-root}}"
printf "  MySQL password: "
read -rs DB_PASS
echo ""
q() { MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER_IN" -N -B "$DB" -e "$1"; }
q 'select 1' >/dev/null || { echo "  ERROR: cannot log in to MySQL or no database $DB"; exit 1; }
if [ -n "$(MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER_IN" -N -e 'SHOW REPLICA STATUS' 2>/dev/null)" ]; then
    echo "  REFUSED: MySQL on $(hostname) is a replica. Run this item on the primary (server01, or the server that ran 55)."
    exit 1
fi

rows="$(q "SELECT CONCAT_WS('|', rc.raceClassId, IFNULL(DATE_FORMAT(rc.firstStartTime, '%Y-%m-%d %H:%i:%s'), ''),
  IF(rc.maxAfterForChaseStart > 0, IFNULL(DATE_FORMAT(rc.firstStartTime + INTERVAL (rc.maxAfterForChaseStart DIV 100) SECOND,
  '%Y-%m-%d %H:%i:%s'), ''), ''))
  FROM raceclasses rc JOIN eventclasses ec ON ec.eventClassId = rc.eventClassId WHERE ec.name = '$CLASS' AND rc.relayLeg = $LEG")"
[ -n "$rows" ] || { echo "  ERROR: no class '$CLASS' with leg $LEG in $DB (names: $(q 'SELECT GROUP_CONCAT(name) FROM eventclasses'))"; exit 1; }
[ "$(printf '%s\n' "$rows" | wc -l)" -eq 1 ] || { echo "  ERROR: more than one race class for $CLASS leg $LEG in $DB"; exit 1; }
IFS='|' read -r RCID FIRST DEFAULT <<< "$rows"
echo "  Class      : $CLASS leg $LEG (raceClassId $RCID)"
echo "  Chase start: ${FIRST:-not set}"
echo "  Default    : ${DEFAULT:-none (no wave limit in OLA): give the time}"
q "SELECT CONCAT('  Runners    : ', COUNT(*), ' on the leg, ', SUM(allocatedStartTime IS NOT NULL), ' with a start time, ',
  SUM(runnerStatus = 'notActivated' AND allocatedStartTime IS NULL), ' without one (these get the wave start)')
  FROM results WHERE raceClassId = $RCID"
if [ -z "$WANT" ]; then
    printf "  Wave start time [%s]: " "${DEFAULT:-HH:MM:SS}"
    read -r WANT
fi
WANT="${WANT:-$DEFAULT}" GIVEN="${WANT:-$DEFAULT}"
# A bare time takes the chase start's date, or the day after when it would be before the chase start (Herrkavlen
# goes past midnight).
if [[ "$WANT" =~ ^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
    [ -n "$FIRST" ] || { echo "  ERROR: no chase start in OLA to take the date from: give YYYY-MM-DD HH:MM:SS"; exit 1; }
    [ ${#WANT} -eq 5 ] && WANT="$WANT:00"
    WANT="$(q "SELECT DATE_FORMAT(IF(TIMESTAMP(DATE('$FIRST'), '$WANT') < '$FIRST', TIMESTAMP(DATE('$FIRST') + INTERVAL 1 DAY, '$WANT'),
      TIMESTAMP(DATE('$FIRST'), '$WANT')), '%Y-%m-%d %H:%i:%s')")"
    [ "$WANT" = NULL ] && WANT="$GIVEN"
fi
[[ "$WANT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || { echo "  ERROR: bad time '$WANT' (HH:MM[:SS] or YYYY-MM-DD HH:MM[:SS])"; exit 1; }
[ "$(q "SELECT STR_TO_DATE('$WANT', '%Y-%m-%d %H:%i:%s') IS NOT NULL")" = 1 ] || { echo "  ERROR: bad time '$WANT'"; exit 1; }
echo ""
printf "  Type YES to give the runners without a start time the wave start %s: " "$WANT"
read -r confirm
[ "$confirm" = YES ] || { echo "  Cancelled."; exit 0; }
n="$(q "UPDATE results SET allocatedStartTime = '$WANT', startTime = '$WANT', modifyDate = NOW()
  WHERE raceClassId = $RCID AND runnerStatus = 'notActivated' AND allocatedStartTime IS NULL; SELECT ROW_COUNT();")" \
  || { echo "  Wave start FAILED"; exit 1; }
echo "  Wave start SET: $n runners of $CLASS leg $LEG start at $WANT."
q "SELECT CONCAT('  Now        : ', SUM(allocatedStartTime IS NOT NULL), ' of ', COUNT(*), ' have a start time, ',
  SUM(allocatedStartTime = '$WANT'), ' in the wave start') FROM results WHERE raceClassId = $RCID"
