#!/bin/bash
echo "--- MySQL / MariaDB Status ---"
echo ""
echo "[ systemd service ]"
systemctl is-active mysql 2>/dev/null || systemctl is-active mariadb 2>/dev/null || echo "Neither mysql nor mariadb service found"
echo ""

echo "[ process check ]"
pgrep -a mysqld 2>/dev/null || echo "No mysqld process running"
echo ""

echo "[ port 3306 ]"
ss -tlnp | grep 3306 || echo "Nothing listening on 3306"
echo ""

echo "[ quick connectivity test ]"
mysqladmin -u root status 2>&1 || sudo mysqladmin -u root status 2>&1
