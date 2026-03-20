#!/usr/bin/bash

set -euo pipefail

cp /etc/resolv.conf /tmp/resolv.conf
su -c 'umount /etc/resolv.conf'
cp /tmp/resolv.conf /etc/resolv.conf

nohup /opt/expressvpn/bin/expressvpn-daemon 2>&1 >/dev/null &
until expressvpnctl status >/dev/null 2>&1; do
  sleep 1
done

expressvpnctl background enable
expressvpnctl set autoconnect true
expressvpnctl set region "${REGION}"
expressvpnctl set protocol "${PROTOCOL}"
expressvpnctl set networklock false

token_file=/tmp/evpn_login_token.txt
printf '%s\n' "$ACTIVATION_CODE" > "$token_file"

login_with_retries() {
  local attempt=1
  for delay in 2 5 10 15 20; do
    echo "[entrypoint] Login attempt ${attempt}..."
    set +e
    login_output="$(expressvpnctl -t 25 login "$token_file" 2>&1)"
    login_status=$?
    set -e

    if [ -n "$login_output" ]; then
      echo "$login_output"
    fi

    if [ "$login_status" -eq 0 ]; then
      echo "[entrypoint] Login succeeded on attempt ${attempt}."
      return 0
    fi

    if echo "$login_output" | grep -qi "Already logged into account"; then
      echo "[entrypoint] Account already logged in; treating as success."
      return 0
    fi

    echo "[entrypoint] Login attempt ${attempt} failed; retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  echo "[entrypoint] Login failed after multiple attempts."
  return 1
}

connect_with_retries() {
  local attempt=1
  for delay in 2 5 10 15 20; do
    echo "[entrypoint] Connect attempt ${attempt} to ${SERVER}..."
    if expressvpnctl -t 30 connect "${SERVER}"; then
      echo "[entrypoint] Connect succeeded on attempt ${attempt}."
      return 0
    fi
    echo "[entrypoint] Connect attempt ${attempt} failed; retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  echo "[entrypoint] Connect failed after multiple attempts."
  return 1
}

if ! login_with_retries; then
  expressvpnctl set networklock true
  exit 1
fi

if ! connect_with_retries; then
  expressvpnctl set networklock true
  exit 1
fi

for _ in {1..20}; do
  if [ "$(expressvpnctl get connectionstate)" = "Connected" ]; then
    break
  fi
  sleep 1
done

if [ "$(expressvpnctl get connectionstate)" != "Connected" ]; then
  expressvpnctl set networklock true
  exit 1
fi

expressvpnctl set networklock true

exec "$@"