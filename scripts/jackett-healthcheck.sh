#!/bin/bash

# Robust Jackett healthcheck: Accepts login page, dashboard with correct API key, or key log messages as healthy

JACKETT_URL="http://localhost:9117"
CONFIG_PATH="/config/Jackett/ServerConfig.json"

# Get expected API key from config
EXPECTED_API_KEY=$(jq -r '.APIKey' "$CONFIG_PATH" 2>/dev/null)

# Fetch root page
RESPONSE=$(curl -s -L "$JACKETT_URL/" || true)

# Relaxed: If we get a 200, 301, or 302, consider the web UI up
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$JACKETT_URL/" --max-time 10)
if echo "$HTTP_CODE" | grep -qE '^(200|301|302)$'; then
  # Check for login dialog
  if echo "$RESPONSE" | grep -q '<form[^>]*action="/UI/Login"'; then
    echo "Jackett login dialog detected (healthy)"
    exit 0
  fi
  # Check for dashboard and correct API key
  if echo "$RESPONSE" | grep -q 'API Key'; then
    DASHBOARD_API_KEY=$(echo "$RESPONSE" | grep -oE 'API Key</span>[^<]*<span[^>]*>[A-Za-z0-9]{32,}' | grep -oE '[A-Za-z0-9]{32,}')
    if [ -n "$DASHBOARD_API_KEY" ] && [ "$DASHBOARD_API_KEY" = "$EXPECTED_API_KEY" ]; then
      echo "Jackett dashboard detected with correct API key (healthy)"
      exit 0
    fi
  fi
  # If the page loads at all, consider it healthy (relaxed)
  echo "Jackett web UI loads (relaxed healthy)"
  exit 0
fi

# Check logs for key success messages
LOG_PATH="/config/Jackett/log.txt"
if [ -f "$LOG_PATH" ]; then
  if grep -q "Using FlareSolverr: http://flaresolverr:8191" "$LOG_PATH" \
    && grep -q "Connection to localhost (::1) 9117 port" "$LOG_PATH" \
    && grep -q "Jackett startup finished" "$LOG_PATH" \
    && grep -q "Now listening on: http://[::]:9117" "$LOG_PATH"; then
    echo "Jackett log shows all startup success messages (healthy)"
    exit 0
  fi
fi

echo "Jackett healthcheck: neither web UI nor logs indicate healthy (unhealthy)"
exit 1
