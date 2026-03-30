#!/bin/bash
# Healthcheck script for qBittorrent: verifies login and Jackett API key

QBITTORRENT_URL="http://localhost:8080"
QBITTORRENT_USER="admin"
QBITTORRENT_PASS="temp03202026"
EXPECTED_API_KEY="cwgfqc90uk7fu634md5k8eoqgmp7ycor"

# Login and get cookie
COOKIE=$(curl -s -i -X POST -d "username=$QBITTORRENT_USER&password=$QBITTORRENT_PASS" "$QBITTORRENT_URL/api/v2/auth/login" | grep -i 'set-cookie' | awk '{print $2}' | cut -d';' -f1)

if [ -z "$COOKIE" ]; then
  echo "qBittorrent login failed"
  exit 1
fi

# Check Jackett API key in config (mounted as /config/qBittorrent.conf)
API_KEY=$(grep -oP 'QBITTORRENT_JACKETT_API_KEY=\K[a-z0-9]{32}' /config/qBittorrent.conf)

if [ "$API_KEY" != "$EXPECTED_API_KEY" ]; then
  echo "qBittorrent Jackett API key mismatch: got $API_KEY, expected $EXPECTED_API_KEY"
  exit 1
fi

echo "qBittorrent login and Jackett API key check passed"
exit 0
