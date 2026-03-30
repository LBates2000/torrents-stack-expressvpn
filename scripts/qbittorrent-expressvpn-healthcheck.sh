#!/bin/bash
# Healthcheck: qBittorrent can reach expressvpn (test via default gateway)
if ! ip route | grep -q 'default via'; then
  echo "qBittorrent cannot find default gateway (expressvpn)"
  exit 1
fi
# Test ping to expressvpn container (should be default gateway)
GATEWAY=$(ip route | awk '/default/ {print $3}')
if ! ping -c 1 -W 2 "$GATEWAY" >/dev/null; then
  echo "qBittorrent cannot ping expressvpn gateway ($GATEWAY)"
  exit 1
fi
echo "qBittorrent can reach expressvpn gateway ($GATEWAY)"
exit 0
