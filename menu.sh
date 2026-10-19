#!/bin/bash
# ============================================================
#  10mila Operations Menu — displayed at login, sourced from ~/.bashrc
#  The same number does the same thing on every server (server01, server02, server03, AWS):
#  1x OLA service   2x backups here   3x send a backup   4x restore   5x database role   6x status
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$SCRIPT_DIR/scripts"
CONFIG_FILE="$HOME/.10mila_menu.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<CONF
LAST_SOURCEDB=tiomila2026
LAST_BACKUP_FILE=
BACKUP_DIR=$HOME/backups
DB_USER=root
CONF
fi
source "$CONFIG_FILE"

on_off() { systemctl is-active --quiet "$1" 2>/dev/null && echo "[ON] " || echo "[off]"; }

show_menu() {
    local target; target=$(bash "$S/50_switch_mysql_target.sh" status 2>/dev/null)
    clear
    echo "=============================================="
    echo "   10mila Operations Menu   $(hostname)"
    echo "   $(date '+%Y-%m-%d %H:%M:%S')    OLA database: ${target}"
    echo "=============================================="
    echo ""
    echo "  OLA SERVICE"
    echo "  11.  Start OLA                 12.  Stop OLA"
    echo "  13.  Autostart on              14.  Autostart off"
    echo "  15.  Service status            16.  Service log (live)"
    echo ""
    echo "  BACKUP ON THIS SERVER"
    echo "  21.  Backup now"
    echo "  22.  Auto-backup every 15 min on  $(on_off 10mila-autobackup.timer)"
    echo "  23.  Auto-backup off"
    echo "  24.  Show last backup"
    echo ""
    echo "  SEND LAST BACKUP TO"
    echo "  31.  server01    32.  server02    33.  server03"
    echo "  34.  AWS OLA     35.  utility"
    echo "  36.  Auto-send new backups on  $(on_off 10mila-autopush.timer)"
    echo "  37.  Auto-send off"
    echo ""
    echo "  RESTORE ON THIS SERVER (overwrites the database)"
    echo "  41.  Restore database from a backup"
    echo "  42.  Restore and start replication from a source"
    echo ""
    echo "  DATABASE ROLE"
    echo "  51.  OLA uses local MySQL      52.  OLA uses server01"
    echo "  53.  OLA uses server02         54.  OLA uses server03"
    echo "  55.  Stop replication: this server becomes the primary"
    echo "  56.  Re-initialize replication (fix settings, no restore)"
    echo ""
    echo "  STATUS"
    echo "  61.  MySQL status   62.  Replica status   63.  Source status"
    echo "  69.  Edit menu config"
    echo ""
    echo "   0.  Exit to shell"
    echo "----------------------------------------------"
    printf "  Choice: "
}

run() { local s="$S/$1"; shift; [ -f "$s" ] && bash "$s" "$@" || echo "ERROR: Script not found: $s"; }

while true; do
    show_menu
    read -r choice || break
    case "$choice" in
        11) run 11_start_ola.sh ;;            12) run 12_stop_ola.sh ;;
        13) run 13_enable_autostart.sh ;;     14) run 14_disable_autostart.sh ;;
        15) run 15_service_status.sh ;;       16) run 16_show_logs.sh ;;
        21) run 21_backup_db.sh ;;            22) run 22_enable_autobackup.sh ;;
        23) run 23_disable_autobackup.sh ;;   24) run 24_show_last_backup.sh ;;
        31) run 30_send_backup.sh server01 ;; 32) run 30_send_backup.sh server02 ;;
        33) run 30_send_backup.sh server03 ;; 34) run 30_send_backup.sh aws ;;
        35) run 30_send_backup.sh util ;;
        36) run 36_enable_autopush.sh ;;      37) run 37_disable_autopush.sh ;;
        41) run 41_restore_db.sh ;;           42) run 42_restore_and_replicate.sh ;;
        51) run 50_switch_mysql_target.sh local ;;    52) run 50_switch_mysql_target.sh server01 ;;
        53) run 50_switch_mysql_target.sh server02 ;; 54) run 50_switch_mysql_target.sh server03 ;;
        55) run 55_stop_replication.sh ;;     56) run 56_reinit_replication.sh ;;
        61) run 61_mysql_status.sh ;;         62) run 62_debug_replication.sh ;;
        63) run 63_debug_source_status.sh ;;  69) ${EDITOR:-nano} "$CONFIG_FILE" ;;
        0)  echo ""; echo "Exiting to shell."; break ;;
        "") ;;
        *)  echo ""; echo "  Unknown option: $choice"; sleep 1 ;;
    esac
    if [ "$choice" != "16" ]; then
        echo ""
        printf "  Press Enter to return to menu..."
        read -r || break
    fi
done
