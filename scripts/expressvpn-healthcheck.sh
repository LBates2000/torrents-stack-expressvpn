#!/bin/bash
set -euo pipefail

MODE="${EXPRESSVPN_HEALTHCHECK_MODE:-strict}"
STATUS_OUTPUT="$(expressvpnctl status 2>/dev/null || true)"

if [ -z "$STATUS_OUTPUT" ]; then
  echo "ExpressVPN daemon status is unavailable"
  exit 1
fi

VPN_STATUS="$(expressvpnctl get connectionstate 2>/dev/null || true)"

if [ "$MODE" = "relaxed" ]; then
  echo "ExpressVPN daemon is reachable (relaxed mode, state: ${VPN_STATUS:-unknown})"
  exit 0
fi

if [ "$VPN_STATUS" != "Connected" ]; then
  echo "ExpressVPN not connected (status: ${VPN_STATUS:-unknown})"
  echo "$STATUS_OUTPUT" | sed -n '1,4p'
  exit 1
fi

if ! getent hosts example.com >/dev/null 2>&1; then
  echo "ExpressVPN connected but DNS resolution failed"
  exit 1
fi

if ! curl -sfI --max-time 10 https://www.google.com >/dev/null; then
  echo "ExpressVPN connected but web access failed"
  exit 1
fi

echo "ExpressVPN connected with working DNS and web access"
exit 0