#!/bin/bash
# Menu 37: stop sending backups automatically.
echo "--- Disable automatic sending of backups ---"
sudo systemctl disable --now 10mila-autopush.timer 2>/dev/null
systemctl is-active --quiet 10mila-autopush.timer && echo "  WARNING: timer still active" || echo "  Auto-send timer is DISABLED"
