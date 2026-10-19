#!/bin/bash
# ============================================================
#  Enable auto-backup every 15 minutes via systemd timer
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
CRED_FILE="$HOME/.10mila_autobackup.cnf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run_autobackup.sh"

source "$CONFIG_FILE"

echo "--- Enable Auto-Backup (every 15 minutes) ---"
echo ""

# ---- Source database (sticky) ----
if [ -n "$LAST_SOURCEDB" ]; then
    printf "  Source database [%s]: " "$LAST_SOURCEDB"
else
    printf "  Source database: "
fi
read -r input_db
SOURCEDB="${input_db:-$LAST_SOURCEDB}"
if [ -z "$SOURCEDB" ]; then echo "ERROR: No database specified."; exit 1; fi

# ---- MySQL user (sticky) ----
DEFAULT_DB_USER="${DB_USER:-root}"
printf "  MySQL user       [%s]: " "$DEFAULT_DB_USER"
read -r input_user
DB_USER="${input_user:-$DEFAULT_DB_USER}"

# ---- MySQL password (always prompt, stored only in secured cnf) ----
printf "  MySQL password: "
read -rs DB_PASS
echo ""

# ---- Backup directory (sticky) ----
DEFAULT_BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
printf "  Backup directory [%s]: " "$DEFAULT_BACKUP_DIR"
read -r input_dir
BACKUP_DIR="${input_dir:-$DEFAULT_BACKUP_DIR}"

echo ""
echo "  Database : $SOURCEDB"
echo "  User     : $DB_USER"
echo "  Backups  : $BACKUP_DIR"
echo "  Schedule : every 15 minutes"
echo "  Rotation : keeps last 96 backups (~24 hours)"
echo ""
printf "  Proceed? [Y/n]: "
read -r confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "  Cancelled."; exit 0; fi

# ---- Write credentials file (MySQL format, chmod 600) ----
cat > "$CRED_FILE" <<EOF
[client]
user=$DB_USER
password=$DB_PASS
EOF
chmod 600 "$CRED_FILE"
echo ""
echo "  Credentials stored in $CRED_FILE (mode 600)"

# ---- Save sticky values to config ----
mkdir -p "$BACKUP_DIR"
sed -i "s|^LAST_SOURCEDB=.*|LAST_SOURCEDB=$SOURCEDB|" "$CONFIG_FILE"
sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" "$CONFIG_FILE"
sed -i "s|^BACKUP_DIR=.*|BACKUP_DIR=$BACKUP_DIR|" "$CONFIG_FILE"

# ---- Install systemd service + timer ----
CURRENT_USER=$(whoami)
HOME_DIR="$HOME"

sudo tee /etc/systemd/system/10mila-autobackup.service > /dev/null <<EOF
[Unit]
Description=10mila Database Auto-Backup
After=mysql.service mariadb.service
Wants=mysql.service mariadb.service

[Service]
Type=oneshot
User=$CURRENT_USER
Environment="HOME=$HOME_DIR"
ExecStart=/bin/bash $RUNNER
StandardOutput=journal
StandardError=journal
SyslogIdentifier=10mila-autobackup
EOF

sudo tee /etc/systemd/system/10mila-autobackup.timer > /dev/null <<EOF
[Unit]
Description=10mila Database Auto-Backup Timer (every 15 min)
Requires=10mila-autobackup.service

[Timer]
OnCalendar=*:0/15
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now 10mila-autobackup.timer

echo ""
if systemctl is-active --quiet 10mila-autobackup.timer; then
    echo "  Auto-backup timer is ACTIVE"
    echo ""
    echo "  Next runs:"
    systemctl list-timers 10mila-autobackup.timer --no-pager 2>/dev/null | head -5
else
    echo "  WARNING: Timer did not start — check: journalctl -u 10mila-autobackup"
fi
