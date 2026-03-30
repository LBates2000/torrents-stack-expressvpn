#!/bin/bash
# Shared healthcheck: verify DNS and web access
# Usage: ./shared-dns-web-healthcheck.sh <service-name>
SERVICE_NAME="$1"

if [ -z "$SERVICE_NAME" ]; then
  SERVICE_NAME="Service"
fi

# Test DNS resolution
if ! getent hosts example.com >/dev/null; then
  echo "$SERVICE_NAME: DNS resolution failed"
  exit 1
fi

# Test HTTP access
if ! curl -sfI https://www.google.com >/dev/null; then
  echo "$SERVICE_NAME: Web access failed"
  exit 1
fi

echo "$SERVICE_NAME: DNS and web access OK"
exit 0
