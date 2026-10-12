#!/bin/bash
# ============================================================
#  10mila Operations Menu
#  Displayed at login — sourced from ~/.bashrc
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.10mila_menu.conf"

# Ensure config file exists with defaults
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'EOF'
LAST_SOURCEDB=tiomila2025
LAST_BACKUP_FILE=/home/user/backups/tiomila2025_auto_2026-03-19T200000Z.sql
BACKUP_DIR=/home/user/backups
PRIMARY_HOST=192.168.1.21
SECONDARY_HOST=192.168.1.22
SECONDARY_USER=user
SECONDARY_PATH=/home/user/backups
ONLINE_HOST=10mila.duckdns.org
ONLINE_USER=ec2-user
ONLINE_PATH=/home/ec2-user/backups
PEM_FILE=/home/user/.ssh/10mila2026.pem
DB_USER=root
EOF
fi

source "$CONFIG_FILE"

timer_status() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo "[ON] "
    else
        echo "[off]"
    fi
}

show_menu() {
    local ab_status ul_status db_target
    ab_status=$(timer_status 10mila-autobackup.timer)
    ul_status=$(timer_status 10mila-autoupload-secondary.timer)
    db_target=$("$SCRIPT_DIR/scripts/14_switch_mysql_target.sh" status 2>/dev/null)
    clear
    echo "=============================================="
    echo "   10mila Operations Menu"
    echo "   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="
    echo ""
    echo "  SERVICE"
    echo "   1.  Start  ola10mila service"
    echo "   2.  Stop   ola10mila service"
    echo "  14.  Switch OLA database: local / server01    [${db_target}]"
    echo ""
    echo "  BACKUP"
    echo "   3.  Create database snapshot/backup"
    echo "   4.  Send backup to secondary server"
    echo "   5.  Send backup to online server"
    echo "   6.  Enable  auto-backup every 15 min       ${ab_status}"
    echo "   7.  Disable auto-backup every 15 min"
    echo "   8.  Restore database from backup"
    echo "   9.  Restore database and start replication"
    echo ""
    echo "  AUTOSTART"
    echo "  10.  Enable  autostart for ola10mila"
    echo "  11.  Disable autostart for ola10mila"
    echo "  12.  Enable  auto-upload to secondary server ${ul_status}"
    echo "  13.  Disable auto-upload to secondary server"
    echo ""
    echo "  TROUBLESHOOTING"
    echo "  20.  Show service status"
    echo "  21.  Show service logs (live)"
    echo "  22.  Show MySQL status"
    echo "  23.  Show last backup file"
    echo "  24.  Edit menu config"
    echo "  25.  Debug replication status (replica)"
    echo "  26.  Debug replication status (master/source)"
    echo "  27.  Re-initialize replication (fix settings, no restore)"
    echo ""
    echo "   0.  Exit to shell"
    echo "----------------------------------------------"
    printf "  Choice: "
}

run_script() {
    local script="$SCRIPT_DIR/scripts/$1"
    if [ -x "$script" ]; then
        "$script"
    else
        echo "ERROR: Script not found or not executable: $script"
    fi
}

while true; do
    show_menu
    read -r choice

    case "$choice" in
        1)  run_script "01_start_ola.sh" ;;
        2)  run_script "02_stop_ola.sh" ;;
        3)  run_script "03_backup_db.sh" ;;
        4)  run_script "04_send_backup_secondary.sh" ;;
        5)  run_script "05_send_backup_online.sh" ;;
        6)  run_script "06_enable_autobackup.sh" ;;
        7)  run_script "07_disable_autobackup.sh" ;;
        8)  run_script "08_restore_db.sh" ;;
        9)  run_script "09_restore_and_replicate.sh" ;;
        10) run_script "10_enable_autostart.sh" ;;
        11) run_script "11_disable_autostart.sh" ;;
        12) run_script "12_enable_autoupload_secondary.sh" ;;
        13) run_script "13_disable_autoupload_secondary.sh" ;;
        14) run_script "14_switch_mysql_target.sh" ;;
        20) run_script "20_service_status.sh" ;;
        21) run_script "21_show_logs.sh" ;;
        22) run_script "22_mysql_status.sh" ;;
        23) run_script "23_show_last_backup.sh" ;;
        24) ${EDITOR:-nano} "$CONFIG_FILE" ;;
        25) run_script "25_debug_replication.sh" ;;
        26) run_script "26_debug_master_status.sh" ;;
        27) run_script "27_reinit_replication.sh" ;;
        0)  echo ""; echo "Exiting to shell."; break ;;
        "")  ;; # ignore empty input
        *)  echo ""; echo "  Unknown option: $choice"; sleep 1 ;;
    esac

    if [ "$choice" != "21" ]; then
        echo ""
        printf "  Press Enter to return to menu..."
        read -r
    fi
done
