#!/bin/bash
echo "--- ola10mila Live Logs (Ctrl+C to stop) ---"
echo ""
journalctl -u ola10mila -f --no-pager
