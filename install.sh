#!/bin/bash
# ============================================================
#  10mila Menu Installer
#  Run once on the Ubuntu server as the target user.
#  Usage:  python3 setup.py          (strips CRLF + installs)
#          python3 setup.py --uninstall
# ============================================================

INSTALL_DIR="$HOME/.10mila_menu"
BASHRC="$HOME/.bashrc"
MARKER="# 10mila-menu"

if [ "$1" == "--uninstall" ]; then
    echo "--- Uninstalling 10mila menu ---"
    sed -i "/$MARKER/,+1d" "$BASHRC"
    rm -rf "$INSTALL_DIR"
    echo "Done. Re-login to apply."
    exit 0
fi

echo "--- Installing 10mila menu to $INSTALL_DIR ---"

# Copy scripts
mkdir -p "$INSTALL_DIR/scripts"
SCRIPT_SOURCE="$(cd "$(dirname "$0")" && pwd)"

cp "$SCRIPT_SOURCE/menu.sh" "$INSTALL_DIR/menu.sh"
cp "$SCRIPT_SOURCE/scripts/"*.sh "$INSTALL_DIR/scripts/"

# Strip Windows CRLF line endings
sed -i 's/\r$//' "$INSTALL_DIR/menu.sh"
sed -i 's/\r$//' "$INSTALL_DIR/scripts/"*.sh

# Make all scripts executable
chmod +x "$INSTALL_DIR/menu.sh"
chmod +x "$INSTALL_DIR/scripts/"*.sh

echo "Scripts installed (CRLF stripped)."

# Add to .bashrc (only if not already present)
if ! grep -q "$MARKER" "$BASHRC"; then
    cat >> "$BASHRC" <<EOF

$MARKER
# Only show menu for interactive SSH/terminal logins (not for scripts/cron)
if [[ \$- == *i* ]] && [ -n "\$PS1" ]; then
    bash "$INSTALL_DIR/menu.sh"
fi
EOF
    echo ".bashrc updated."
else
    echo ".bashrc already configured — skipping."
fi

# Sudoers: allow specific commands without password prompt
SUDOERS_FILE="/etc/sudoers.d/10mila_menu"
CURRENT_USER=$(whoami)
echo ""
echo "--- Configuring sudo (requires sudo access) ---"
sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Allow $CURRENT_USER to manage ola10mila and auto-backup without password prompt
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start ola10mila
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ola10mila
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable ola10mila
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable ola10mila
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable --now 10mila-autobackup.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable --now 10mila-autobackup.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable 10mila-autobackup.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/systemd/system/10mila-autobackup.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/systemd/system/10mila-autobackup.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable --now 10mila-autoupload-secondary.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable --now 10mila-autoupload-secondary.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable 10mila-autoupload-secondary.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/systemd/system/10mila-autoupload-secondary.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/systemd/system/10mila-autoupload-secondary.timer
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/mysqldump
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/mysqladmin
EOF
sudo chmod 440 "$SUDOERS_FILE"
echo "Sudoers configured: $SUDOERS_FILE"

echo ""
echo "=============================================="
echo "  Installation complete!"
echo "  Re-login (or run: bash $INSTALL_DIR/menu.sh)"
echo "=============================================="
