#!/bin/bash
echo "--- Disable Auto-Backup ---"
echo ""

# Check current state
if ! systemctl is-active --quiet 10mila-autobackup.timer 2>/dev/null; then
    echo "  Auto-backup timer is already inactive."
else
    printf "  Stop and disable auto-backup? [Y/n]: "
    read -r confirm
    confirm="${confirm:-Y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "  Cancelled."; exit 0; fi

    sudo systemctl disable --now 10mila-autobackup.timer
    sudo systemctl disable 10mila-autobackup.service 2>/dev/null

    echo ""
    if systemctl is-active --quiet 10mila-autobackup.timer 2>/dev/null; then
        echo "  WARNING: Timer is still active — check manually"
    else
        echo "  Auto-backup timer is DISABLED"
    fi
fi

echo ""
printf "  Also remove stored MySQL credentials? [y/N]: "
read -r rm_cred
rm_cred="${rm_cred:-N}"
if [[ "$rm_cred" =~ ^[Yy]$ ]]; then
    rm -f "$HOME/.10mila_autobackup.cnf"
    echo "  Credentials file removed."
else
    echo "  Credentials file kept (will be reused when re-enabling)."
fi
