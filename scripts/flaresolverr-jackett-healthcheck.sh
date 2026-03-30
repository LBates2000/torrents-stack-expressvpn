#!/bin/bash
# Healthcheck: FlareSolverr can reach Jackett
JACKETT_URL="http://jackett:9117"
if ! curl -sfI "$JACKETT_URL" >/dev/null; then
  echo "FlareSolverr cannot reach Jackett"
  exit 1
fi
echo "FlareSolverr can reach Jackett"
exit 0
