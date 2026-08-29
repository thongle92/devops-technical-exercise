#!/usr/bin/env bash
# Summarize a load.sh CSV: total requests, count by http_code, and max
# latency observed.
set -euo pipefail

FILE="${1:?usage: summarize.sh <csv-file>}"

echo "=== $FILE ==="
total=$(($(wc -l < "$FILE") - 1))
echo "total requests: $total"
echo "by http_code:"
tail -n +2 "$FILE" | cut -d, -f2 | sort | uniq -c | sort -rn
echo "max latency (s): $(tail -n +2 "$FILE" | cut -d, -f3 | sort -n | tail -1)"
