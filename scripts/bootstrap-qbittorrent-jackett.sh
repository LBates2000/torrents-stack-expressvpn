#!/usr/bin/env bash

set -euo pipefail

QBITTORRENT_CONFIG_DIR="${QBITTORRENT_CONFIG_DIR:-/config/qBittorrent}"
QBITTORRENT_CONF="${QBITTORRENT_CONF:-${QBITTORRENT_CONFIG_DIR}/qBittorrent.conf}"
ENGINES_DIR="${QBITTORRENT_ENGINES_DIR:-${QBITTORRENT_CONFIG_DIR}/nova3/engines}"
PLUGIN_PATH="${ENGINES_DIR}/jackett.py"
CONFIG_PATH="${ENGINES_DIR}/jackett.json"
JACKETT_CONFIG_PATH="${JACKETT_CONFIG_PATH:-/config/Jackett/ServerConfig.json}"
JACKETT_PLUGIN_URL="${QBITTORRENT_JACKETT_PLUGIN_URL:-https://raw.githubusercontent.com/qbittorrent/search-plugins/fa0be6abdc47b8622e8ec71a0d4427d9a7770eab/nova3/engines/jackett.py}"
JACKETT_URL="${QBITTORRENT_JACKETT_URL:-http://jackett:9117}"
THREAD_COUNT="${QBITTORRENT_JACKETT_THREAD_COUNT:-20}"
TRACKER_FIRST="${QBITTORRENT_JACKETT_TRACKER_FIRST:-false}"
QBITTORRENT_WEBUI_URL="${QBITTORRENT_WEBUI_URL:-http://127.0.0.1:${WEBUI_PORT:-8080}}"
QBITTORRENT_WEBUI_USERNAME="${QBITTORRENT_WEBUI_USERNAME:-admin}"
QBITTORRENT_DEFAULT_SAVE_PATH="${QBITTORRENT_CFG_DOWNLOADS_SAVE_PATH:-/downloads/}"
QBITTORRENT_TEMP_SAVE_PATH="${QBITTORRENT_CFG_DOWNLOADS_TEMP_PATH:-/downloads/incomplete/}"

mkdir -p "${QBITTORRENT_CONFIG_DIR}" "${ENGINES_DIR}"

trim_trailing_slash() {
  local value="${1:-}"
  while [ "${#value}" -gt 1 ] && [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf '%s' "$value"
}

apply_download_preferences() {
  if [ -z "${QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT:-}" ]; then
    echo "[qbittorrent-bootstrap] Skipping Web API preference sync because QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT is not set"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "[qbittorrent-bootstrap] WARN: curl is unavailable; cannot sync qBittorrent save paths via Web API"
    return 0
  fi

  local default_save_path
  local temp_save_path
  local cookie_jar
  local status_code
  local login_response
  local preferences_json

  default_save_path="$(trim_trailing_slash "$QBITTORRENT_DEFAULT_SAVE_PATH")"
  temp_save_path="$(trim_trailing_slash "$QBITTORRENT_TEMP_SAVE_PATH")"
  cookie_jar="$(mktemp)"

  for _ in $(seq 1 30); do
    status_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${QBITTORRENT_WEBUI_URL}/" || true)"
    case "$status_code" in
      200|302|403)
        break
        ;;
    esac
    sleep 2
  done

  login_response="$(curl -fsS --cookie-jar "$cookie_jar" \
    --data-urlencode "username=${QBITTORRENT_WEBUI_USERNAME}" \
    --data-urlencode "password=${QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT}" \
    "${QBITTORRENT_WEBUI_URL}/api/v2/auth/login" 2>/dev/null || true)"

  if [ "$login_response" != 'Ok.' ]; then
    echo "[qbittorrent-bootstrap] WARN: Could not log in to qBittorrent Web API to sync save paths"
    rm -f "$cookie_jar"
    return 0
  fi

  preferences_json=$(printf '{"save_path":"%s","temp_path":"%s","temp_path_enabled":true}' "$default_save_path" "$temp_save_path")
  if curl -fsS --cookie "$cookie_jar" --data-urlencode "json=${preferences_json}" "${QBITTORRENT_WEBUI_URL}/api/v2/app/setPreferences" >/dev/null; then
    echo "[qbittorrent-bootstrap] Applied qBittorrent save paths via Web API"
  else
    echo "[qbittorrent-bootstrap] WARN: Failed to apply qBittorrent save paths via Web API"
  fi

  rm -f "$cookie_jar"
}

# Download Jackett plugin if missing
if [ ! -s "${PLUGIN_PATH}" ]; then
  if command -v wget >/dev/null 2>&1; then
    if ! timeout 30 wget -q -O "${PLUGIN_PATH}" "${JACKETT_PLUGIN_URL}"; then
      echo "[qbittorrent-bootstrap] WARN: Failed to download jackett.py via wget (timeout or error)"
      rm -f "${PLUGIN_PATH}" || true
    else
      echo "[qbittorrent-bootstrap] Installed jackett.py search plugin"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 - "${JACKETT_PLUGIN_URL}" "${PLUGIN_PATH}" <<'PY'
import sys
from urllib.request import urlopen
import socket
url, dest = sys.argv[1], sys.argv[2]
try:
    with urlopen(url, timeout=30) as response:
        content = response.read()
    with open(dest, 'wb') as fh:
        fh.write(content)
except (socket.timeout, Exception) as e:
    sys.exit(1)
PY
    then
      echo "[qbittorrent-bootstrap] WARN: Failed to download jackett.py via python3 (timeout or error)"
      rm -f "${PLUGIN_PATH}" || true
    else
      echo "[qbittorrent-bootstrap] Installed jackett.py search plugin"
    fi
  else
    echo "[qbittorrent-bootstrap] WARN: Neither wget nor python3 available; cannot auto-install jackett.py"
  fi
fi


JACKETT_API_KEY="${QBITTORRENT_JACKETT_API_KEY:-}"

if [ -z "${JACKETT_API_KEY}" ] && [ -f "${JACKETT_CONFIG_PATH}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    JACKETT_API_KEY="$(python3 - "${JACKETT_CONFIG_PATH}" <<'PY'
import json
import sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    value = data.get('APIKey')
    if isinstance(value, str):
        print(value)
except Exception:
    pass
PY
)"
  else
    JACKETT_API_KEY="$(grep -oE '"APIKey"\s*:\s*"[^"]+"' "${JACKETT_CONFIG_PATH}" | sed -E 's/.*"APIKey"\s*:\s*"([^"]+)".*/\1/' | head -n 1 || true)"
  fi
fi


if [ -z "${JACKETT_API_KEY}" ]; then
  echo "[qbittorrent-bootstrap] WARN: Jackett API key not found; leaving ${CONFIG_PATH} unchanged"
else
  cat > "${CONFIG_PATH}" <<EOF
{
    "api_key": "${JACKETT_API_KEY}",
    "thread_count": ${THREAD_COUNT},
    "tracker_first": ${TRACKER_FIRST},
    "url": "${JACKETT_URL}"
}
EOF

  echo "[qbittorrent-bootstrap] Wrote jackett.json with API key and service URL"

  if grep -q '^QBITTORRENT_JACKETT_API_KEY=' "$QBITTORRENT_CONF" 2>/dev/null; then
    sed -i "s|^QBITTORRENT_JACKETT_API_KEY=.*$|QBITTORRENT_JACKETT_API_KEY=$JACKETT_API_KEY|" "$QBITTORRENT_CONF"
  else
    echo "QBITTORRENT_JACKETT_API_KEY=$JACKETT_API_KEY" >> "$QBITTORRENT_CONF"
  fi
  echo "[qbittorrent-bootstrap] Synced QBITTORRENT_JACKETT_API_KEY to $QBITTORRENT_CONF"
fi

# Set qBittorrent WebUI password hash if QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT is set
if [ -n "${QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT:-}" ]; then
  echo "[qbittorrent-bootstrap] Attempting to set WebUI password hash from QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT..."
  if command -v python3 >/dev/null 2>&1; then
    TMP_PY_SCRIPT="/tmp/qb_webui_hash.py"
    cat > "$TMP_PY_SCRIPT" <<'EOF'
import os, base64, hashlib
password = os.environ.get('QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT')
assert password, 'No password in env'
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), salt, 100000, dklen=64)
out = '@ByteArray({}:{})'.format(
    base64.b64encode(salt).decode(),
    base64.b64encode(dk).decode()
)
print('WebUI\\Password_PBKDF2=' + out)
EOF
    HASH_LINE=$(python3 "$TMP_PY_SCRIPT")
    rm -f "$TMP_PY_SCRIPT"
    echo "[qbittorrent-bootstrap] Generated hash line: $HASH_LINE"
    # Remove any old WebUI password lines
    sed -i '/^WebUI\\Password_ha1=/d' "$QBITTORRENT_CONF"
    sed -i '/^WebUI\\Password_PBKDF2=/d' "$QBITTORRENT_CONF"
    # Ensure [Preferences] section exists
    if ! grep -q '^\[Preferences\]' "$QBITTORRENT_CONF" 2>/dev/null; then
      echo "[Preferences]" >> "$QBITTORRENT_CONF"
    fi
    # Insert password line after [Preferences] section
    awk -v line="$HASH_LINE" 'BEGIN{added=0} /^\[Preferences\]/{print; if(!added){print line; added=1}; next} 1' "$QBITTORRENT_CONF" > "$QBITTORRENT_CONF.tmp" && mv "$QBITTORRENT_CONF.tmp" "$QBITTORRENT_CONF"
    echo "[qbittorrent-bootstrap] Set WebUI password hash in $QBITTORRENT_CONF from QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT"
  else
    echo "[qbittorrent-bootstrap] WARN: python3 not available, cannot set WebUI password hash from QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT"
  fi
else
  echo "[qbittorrent-bootstrap] QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT not set or empty inside the container, skipping WebUI password hash."
fi

apply_download_preferences
