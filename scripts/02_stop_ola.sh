#!/bin/bash
echo "--- Stopping ola10mila service ---"
sudo systemctl stop ola10mila
echo ""
systemctl is-active ola10mila && echo "Service is still running" || echo "Service is STOPPED"
