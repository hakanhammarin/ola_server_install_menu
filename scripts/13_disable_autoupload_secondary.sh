#!/bin/bash
echo "--- Disable Auto-Upload to Secondary Server ---"
echo ""

if ! systemctl is-active --quiet 10mila-autoupload-secondary.timer 2>/dev/null; then
    echo "  Auto-upload timer is already inactive."
else
    printf "  Stop and disable auto-upload? [Y/n]: "
    read -r confirm
    confirm="${confirm:-Y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "  Cancelled."; exit 0; fi

    sudo systemctl disable --now 10mila-autoupload-secondary.timer
    sudo systemctl disable 10mila-autoupload-secondary.service 2>/dev/null

    echo ""
    if systemctl is-active --quiet 10mila-autoupload-secondary.timer 2>/dev/null; then
        echo "  WARNING: Timer is still active — check manually"
    else
        echo "  Auto-upload timer is DISABLED"
    fi
fi

echo ""
printf "  Also remove stored SSH password? [y/N]: "
read -r rm_pass
rm_pass="${rm_pass:-N}"
if [[ "$rm_pass" =~ ^[Yy]$ ]]; then
    rm -f "$HOME/.10mila_secondary.pass"
    echo "  Password file removed."
else
    echo "  Password file kept (will be reused when re-enabling)."
fi
