
#!/usr/bin/bash

# Allowed ExpressVPN regions:
#   netherlands-amsterdam
#   netherlands-rotterdam
#   netherlands-the-hague
#   switzerland
#   switzerland-2

set -euo pipefail

WATCHDOG_INTERVAL_SECONDS="${EXPRESSVPN_WATCHDOG_INTERVAL_SECONDS:-30}"

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
unset ACTIVATION_CODE
chmod 600 "$token_file"

cleanup_token_file() {
  rm -f "$token_file"
}
trap cleanup_token_file EXIT

login_with_retries() {
  local attempt=1
  for delay in 2 5 10 15 20; do
    echo "[entrypoint] Login attempt ${attempt}..."
    set +e
    login_output="$(expressvpnctl -t 25 login "$token_file" 2>&1)"
    login_status=$?
    set -e

    if [ -n "$login_output" ]; then
      echo "[entrypoint] Login command returned output (redacted)."
    fi

    if [ "$login_status" -eq 0 ]; then
      echo "[entrypoint] Login succeeded on attempt ${attempt}."
      return 0
    fi

    if echo "$login_output" | grep -qi "Already logged into account"; then
      echo "[entrypoint] Account already logged in; treating as success."
      return 0
    fi

    echo "[entrypoint] Login attempt ${attempt} failed (details redacted); retrying in ${delay}s..."
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

ensure_reconnectable_networklock() {
  expressvpnctl set networklock false
}

start_reconnect_watchdog() {
  (
    while true; do
      sleep "$WATCHDOG_INTERVAL_SECONDS"
      state="$(expressvpnctl get connectionstate 2>/dev/null || true)"
      case "$state" in
        Connected|Connecting|Reconnecting|DisconnectingToReconnect)
          continue
          ;;
      esac

      echo "[entrypoint] Watchdog detected VPN state '${state:-unknown}'; attempting reconnect..."
      ensure_reconnectable_networklock
      if connect_with_retries; then
        echo "[entrypoint] Watchdog reconnect succeeded."
      else
        echo "[entrypoint] Watchdog reconnect failed; will retry on next interval."
      fi
    done
  ) &
}

if ! login_with_retries; then
  expressvpnctl set networklock true
  exit 1
fi

ensure_reconnectable_networklock

if ! connect_with_retries; then
  expressvpnctl set networklock true
  exit 1
fi

final_state=""
for _ in {1..20}; do
  final_state="$(expressvpnctl get connectionstate 2>/dev/null || true)"
  if [ "$final_state" = "Connected" ]; then
    break
  fi
  sleep 1
done

if [ "$final_state" != "Connected" ]; then
  expressvpnctl set networklock true
  exit 1
fi

ensure_reconnectable_networklock
start_reconnect_watchdog

exec "$@"