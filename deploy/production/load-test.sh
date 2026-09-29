#!/usr/bin/env bash
# Sends realistic traffic at production so the dashboard graphs have something to show.
# Run from AWS CloudShell (or any Linux/Git Bash terminal):
#
#   bash load-test.sh http://<elastic-ip> [duration_seconds=300] [workers=5]
#
# Each loop: open the page, /health, list tasks, create -> complete -> delete a task,
# then hit a missing page once so the 4xx graph has data too.
set -uo pipefail

BASE_URL="${1:?usage: bash load-test.sh http://<elastic-ip> [duration_seconds] [workers]}"
DURATION="${2:-300}"
WORKERS="${3:-5}"
END_TS=$(( $(date +%s) + DURATION ))
JSON='Content-Type: application/json'

worker() {
  local id=$1 loops=0 tid
  while [ "$(date +%s)" -lt "$END_TS" ]; do
    curl -s -o /dev/null "$BASE_URL/"
    curl -s -o /dev/null "$BASE_URL/health"
    curl -s -o /dev/null "$BASE_URL/tasks"
    tid=$(curl -s -X POST -H "$JSON" -d "{\"title\":\"load test w$id-$loops\"}" "$BASE_URL/tasks" \
          | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    if [ -n "$tid" ]; then
      curl -s -o /dev/null -X PATCH -H "$JSON" -d '{"completed":true}' "$BASE_URL/tasks/$tid"
      curl -s -o /dev/null -X DELETE "$BASE_URL/tasks/$tid"
    fi
    curl -s -o /dev/null "$BASE_URL/this-page-does-not-exist"
    loops=$((loops + 1))
  done
  echo "worker $id done: $loops loops ($((loops * 7)) requests)"
}

echo "Load test: $BASE_URL for ${DURATION}s with $WORKERS workers (started $(date -u +%H:%M:%SZ))"
for w in $(seq 1 "$WORKERS"); do worker "$w" & done
wait
echo "Finished $(date -u +%H:%M:%SZ)"
