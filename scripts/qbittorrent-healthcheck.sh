#!/bin/bash
set -euo pipefail

QBITTORRENT_URL="http://localhost:8080/"
QBITTORRENT_CONF="/config/qBittorrent/qBittorrent.conf"
PLUGIN_PY="/config/qBittorrent/nova3/engines/jackett.py"
PLUGIN_JSON="/config/qBittorrent/nova3/engines/jackett.json"

STATUS_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$QBITTORRENT_URL" || true)"
case "$STATUS_CODE" in
  200|302)
    ;;
  *)
    echo "qBittorrent Web UI unhealthy (status: ${STATUS_CODE:-none})"
    exit 1
    ;;
esac

if [ ! -s "$PLUGIN_PY" ] || [ ! -s "$PLUGIN_JSON" ]; then
  echo "qBittorrent Jackett plugin files are missing"
  exit 1
fi

API_KEY="$(grep -oP 'QBITTORRENT_JACKETT_API_KEY=\K[a-z0-9]{32}' "$QBITTORRENT_CONF" 2>/dev/null || true)"
if [ -z "$API_KEY" ]; then
  echo "qBittorrent Jackett API key missing from $QBITTORRENT_CONF"
  exit 1
fi

echo "qBittorrent Web UI reachable and Jackett plugin config present"
exit 0
