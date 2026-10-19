#!/bin/bash
echo "--- Starting ola10mila service ---"
sudo systemctl start ola10mila
echo ""
systemctl is-active ola10mila && echo "Service is RUNNING" || echo "Service did NOT start — check logs (option 16)"
