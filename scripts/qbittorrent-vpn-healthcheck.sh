#!/bin/bash
# Healthcheck for qBittorrent: verify VPN routing, DNS, and web access

# Check for VPN interface (tun0)
if ! ip addr show tun0 >/dev/null 2>&1; then
  echo "VPN interface tun0 not found"
  exit 1
fi

# Delegate DNS and web check to shared script
"$(dirname "$0")/shared-dns-web-healthcheck.sh" "qBittorrent"
