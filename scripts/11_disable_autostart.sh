#!/bin/bash
echo "--- Disable autostart for ola10mila ---"
sudo systemctl disable ola10mila
echo ""
systemctl is-enabled ola10mila && echo "Autostart is still enabled" || echo "Autostart is DISABLED"
