#!/bin/bash
# Healthcheck: Jackett can reach qBittorrent
QBITTORRENT_URL="http://qbittorrent:8080"
if ! curl -sfI "$QBITTORRENT_URL" >/dev/null; then
  echo "Jackett cannot reach qBittorrent"
  exit 1
fi
echo "Jackett can reach qBittorrent"
exit 0
