#!/bin/bash
# Structured healthcheck for qBittorrent: outputs JSON for CI parsing

QBITTORRENT_URL="http://localhost:8080"
QBITTORRENT_USER="admin"
QBITTORRENT_PASS="temp03202026"
EXPECTED_API_KEY="cwgfqc90uk7fu634md5k8eoqgmp7ycor"

result=0
msg=""

COOKIE=$(curl -s -i -X POST -d "username=$QBITTORRENT_USER&password=$QBITTORRENT_PASS" "$QBITTORRENT_URL/api/v2/auth/login" | grep -i 'set-cookie' | awk '{print $2}' | cut -d';' -f1)
if [ -z "$COOKIE" ]; then
  msg="qBittorrent login failed"
  result=1
else
  API_KEY=$(grep -oP 'QBITTORRENT_JACKETT_API_KEY=\K[a-z0-9]{32}' /config/qBittorrent.conf)
  if [ "$API_KEY" != "$EXPECTED_API_KEY" ]; then
    msg="Jackett API key mismatch: got $API_KEY, expected $EXPECTED_API_KEY"
    result=2
  else
    msg="qBittorrent login and Jackett API key check passed"
    result=0
  fi
fi

# Output JSON for CI
jq -n --arg status "$(if [ $result -eq 0 ]; then echo PASS; else echo FAIL; fi)" --arg message "$msg" '{status: $status, message: $message}'
exit $result
