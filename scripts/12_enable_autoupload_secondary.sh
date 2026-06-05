#!/bin/bash
# ============================================================
#  Enable auto-upload of new backups to secondary server
#  Uses sshpass + SCP. Delta: only uploads missing files.
#  Timer runs at :08/:23/:38/:53 — 8 min after each backup.
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
PASS_FILE="$HOME/.10mila_secondary.pass"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run_autoupload_secondary.sh"

source "$CONFIG_FILE"

echo "--- Enable Auto-Upload to Secondary Server ---"
echo ""

# ---- Check sshpass is installed ----
if ! command -v sshpass &>/dev/null; then
    echo "  'sshpass' is required but not installed."
    printf "  Install it now? [Y/n]: "
    read -r inst
    inst="${inst:-Y}"
    if [[ "$inst" =~ ^[Yy]$ ]]; then
        sudo apt-get install -y sshpass
        if ! command -v sshpass &>/dev/null; then
            echo "  ERROR: Installation failed."
            exit 1
        fi
    else
        echo "  Cannot continue without sshpass."
        exit 1
    fi
fi

# ---- Prompts (sticky defaults) ----
DEFAULT_HOST="${SECONDARY_HOST}"
printf "  Secondary host [%s]: " "$DEFAULT_HOST"
read -r input_host
SEC_HOST="${input_host:-$DEFAULT_HOST}"
if [ -z "$SEC_HOST" ]; then echo "  ERROR: Host required."; exit 1; fi

DEFAULT_USER="${SECONDARY_USER:-user}"
printf "  Remote user    [%s]: " "$DEFAULT_USER"
read -r input_user
SEC_USER="${input_user:-$DEFAULT_USER}"

DEFAULT_PATH="${SECONDARY_PATH:-~/backups}"
printf "  Remote path    [%s]: " "$DEFAULT_PATH"
read -r input_path
SEC_PATH="${input_path:-$DEFAULT_PATH}"

DEFAULT_BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
printf "  Local backups  [%s]: " "$DEFAULT_BACKUP_DIR"
read -r input_dir
LOCAL_DIR="${input_dir:-$DEFAULT_BACKUP_DIR}"

# ---- Password (always prompted, stored in secured file) ----
printf "  SSH password: "
read -rs SSH_PASS
echo ""

# ---- Verify credentials with a test connection ----
echo ""
echo "  Testing connection to $SEC_USER@$SEC_HOST ..."
SSHPASS="$SSH_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 -o BatchMode=no \
    "$SEC_USER@$SEC_HOST" "mkdir -p $SEC_PATH && echo OK" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "  ERROR: Could not connect. Check host, user, and password."
    exit 1
fi
echo "  Connection OK."

# ---- Store password securely ----
printf '%s' "$SSH_PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"
echo "  Password stored in $PASS_FILE (mode 600)"

# ---- Save sticky config ----
sed -i "s|^SECONDARY_HOST=.*|SECONDARY_HOST=$SEC_HOST|" "$CONFIG_FILE"
sed -i "s|^SECONDARY_USER=.*|SECONDARY_USER=$SEC_USER|" "$CONFIG_FILE"
sed -i "s|^SECONDARY_PATH=.*|SECONDARY_PATH=$SEC_PATH|" "$CONFIG_FILE"
sed -i "s|^BACKUP_DIR=.*|BACKUP_DIR=$LOCAL_DIR|" "$CONFIG_FILE"

# ---- Install systemd service + timer ----
CURRENT_USER=$(whoami)
HOME_DIR="$HOME"

sudo tee /etc/systemd/system/10mila-autoupload-secondary.service > /dev/null <<EOF
[Unit]
Description=10mila Auto-Upload Backups to Secondary Server
After=network.target

[Service]
Type=oneshot
User=$CURRENT_USER
Environment="HOME=$HOME_DIR"
ExecStart=/bin/bash $RUNNER
StandardOutput=journal
StandardError=journal
SyslogIdentifier=10mila-autoupload-secondary
EOF

# Runs at :08/:23/:38/:53 — 8 min after auto-backup fires at :00/:15/:30/:45
sudo tee /etc/systemd/system/10mila-autoupload-secondary.timer > /dev/null <<EOF
[Unit]
Description=10mila Auto-Upload Secondary Timer
Requires=10mila-autoupload-secondary.service

[Timer]
OnCalendar=*:8/15
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now 10mila-autoupload-secondary.timer

echo ""
if systemctl is-active --quiet 10mila-autoupload-secondary.timer; then
    echo "  Auto-upload timer is ACTIVE"
    echo "  Uploads run at :08/:23/:38/:53 (8 min after each backup)"
    echo ""
    echo "  Next runs:"
    systemctl list-timers 10mila-autoupload-secondary.timer --no-pager 2>/dev/null | head -5
else
    echo "  WARNING: Timer did not start — check: journalctl -u 10mila-autoupload-secondary"
fi
