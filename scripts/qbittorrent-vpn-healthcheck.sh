#!/bin/bash
set -euo pipefail

DEFAULT_ROUTE="$(ip route | awk '/^default / {print; exit}')"
if [ -z "$DEFAULT_ROUTE" ]; then
  echo "qBittorrent default route is missing"
  exit 1
fi

ROUTE_IFACE="$(printf '%s\n' "$DEFAULT_ROUTE" | awk '{print $5}')"
if [ -z "$ROUTE_IFACE" ] || [ "$ROUTE_IFACE" = "lo" ]; then
  echo "qBittorrent default route uses an invalid interface: ${ROUTE_IFACE:-none}"
  exit 1
fi

"$(dirname "$0")/shared-dns-web-healthcheck.sh" "qBittorrent VPN namespace"
