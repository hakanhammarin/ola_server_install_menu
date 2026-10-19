#!/bin/bash
echo "--- Enable autostart for ola10mila ---"
sudo systemctl enable ola10mila
echo ""
systemctl is-enabled ola10mila && echo "Autostart is ENABLED" || echo "Failed to enable autostart"
