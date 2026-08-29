#!/usr/bin/env bash
# Continuous request load against a URL, logging one CSV row per request:
# timestamp,http_code,latency_seconds. http_code=000 means the request
# itself failed (connection refused/reset/timeout), not just a non-2xx
# response.
set -euo pipefail

URL="${1:-http://localhost:8081/}"
OUTFILE="${2:-load.csv}"

echo "timestamp,http_code,latency_seconds" > "$OUTFILE"
while true; do
  ts=$(date +%s.%N)
  result=$(curl -sS -o /dev/null -w "%{http_code},%{time_total}" --max-time 2 "$URL" || echo "000,0")
  echo "$ts,$result" >> "$OUTFILE"
  sleep 0.2
done
