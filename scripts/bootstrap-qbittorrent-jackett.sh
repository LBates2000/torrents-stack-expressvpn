#!/usr/bin/env bash

set -uo pipefail

ENGINES_DIR="${QBITTORRENT_ENGINES_DIR:-/config/qBittorrent/nova3/engines}"
PLUGIN_PATH="${ENGINES_DIR}/jackett.py"
CONFIG_PATH="${ENGINES_DIR}/jackett.json"
JACKETT_CONFIG_PATH="${JACKETT_CONFIG_PATH:-/config/Jackett/ServerConfig.json}"
JACKETT_PLUGIN_URL="${QBITTORRENT_JACKETT_PLUGIN_URL:-https://raw.githubusercontent.com/qbittorrent/search-plugins/fa0be6abdc47b8622e8ec71a0d4427d9a7770eab/nova3/engines/jackett.py}"
JACKETT_URL="${QBITTORRENT_JACKETT_URL:-http://jackett:9117}"
THREAD_COUNT="${QBITTORRENT_JACKETT_THREAD_COUNT:-20}"
TRACKER_FIRST="${QBITTORRENT_JACKETT_TRACKER_FIRST:-false}"

mkdir -p "${ENGINES_DIR}"

if [ ! -s "${PLUGIN_PATH}" ]; then
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "${PLUGIN_PATH}" "${JACKETT_PLUGIN_URL}"; then
      echo "[qbittorrent-bootstrap] Installed jackett.py search plugin"
    else
      echo "[qbittorrent-bootstrap] WARN: Failed to download jackett.py via wget"
      rm -f "${PLUGIN_PATH}" || true
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 - "${JACKETT_PLUGIN_URL}" "${PLUGIN_PATH}" <<'PY'
import sys
from urllib.request import urlopen
url, dest = sys.argv[1], sys.argv[2]
with urlopen(url, timeout=20) as response:
    content = response.read()
with open(dest, 'wb') as fh:
    fh.write(content)
PY
    then
      echo "[qbittorrent-bootstrap] Installed jackett.py search plugin"
    else
      echo "[qbittorrent-bootstrap] WARN: Failed to download jackett.py via python3"
      rm -f "${PLUGIN_PATH}" || true
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
  exit 0
fi

cat > "${CONFIG_PATH}" <<EOF
{
    "api_key": "${JACKETT_API_KEY}",
    "thread_count": ${THREAD_COUNT},
    "tracker_first": ${TRACKER_FIRST},
    "url": "${JACKETT_URL}"
}
EOF

echo "[qbittorrent-bootstrap] Wrote jackett.json with API key and service URL"
