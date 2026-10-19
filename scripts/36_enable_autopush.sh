#!/bin/bash
# Menu 36: send every new backup to AUTOPUSH_TARGETS (default util) every 15 minutes, 8 minutes after each backup.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOME/.10mila_menu.conf"
echo "--- Enable automatic sending of backups to: ${AUTOPUSH_TARGETS:-util} ---"
sudo tee /etc/systemd/system/10mila-autopush.service > /dev/null <<UNIT
[Unit]
Description=10mila: send new backups to ${AUTOPUSH_TARGETS:-util}
After=network-online.target
[Service]
Type=oneshot
User=$(whoami)
Environment="HOME=$HOME"
ExecStart=/bin/bash $SCRIPT_DIR/run_autopush.sh
SyslogIdentifier=10mila-autopush
UNIT
sudo tee /etc/systemd/system/10mila-autopush.timer > /dev/null <<UNIT
[Unit]
Description=10mila: send new backups every 15 min (:08/:23/:38/:53)
[Timer]
OnCalendar=*:8/15
AccuracySec=30s
Persistent=true
[Install]
WantedBy=timers.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now 10mila-autopush.timer
systemctl is-active --quiet 10mila-autopush.timer && echo "  Auto-send timer is ACTIVE" || echo "  WARNING: timer did not start"
