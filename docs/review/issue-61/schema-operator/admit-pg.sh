#!/usr/bin/env bash
set -u
out=/home/agents/dev/pickteams/.limen/task-coordinators/issue-61/review-6
proof="$out/independent_pg_proof.py"
log="$out/independent-pg-proof.log"
sha=$(git rev-parse HEAD)
printf 'DELIVERY_HEAD=%s\nAPPLICATION_BASE=f0384d6e38673bf0f44423514e7749cb316c83d3\nCOMMAND=python3 -B %s\n' "$sha" "$proof" > "$log"
flock -n -E75 /tmp/pickteams-flutter-validation.lock bash -c '
  mem=$(awk '\''/^MemAvailable:/ { print $2 }'\'' /proc/meminfo)
  printf "MemAvailable=%s KiB; required=2621440 KiB\n" "$mem"
  if [ "$mem" -lt 2621440 ]; then
    printf "ADMISSION DENIED BEFORE POSTGRESQL PROOF\n"
    exit 76
  fi
  printf "ADMISSION PASSED; one bounded independent PostgreSQL invocation\n"
  exec python3 -B "$1"
' pg-proof-admission "$proof" >> "$log" 2>&1
result=$?
printf 'EXIT=%s\n' "$result" >> "$log"
if [ "$result" -eq 75 ] || [ "$result" -eq 76 ]; then
  printf 'DELIVERY_HEAD=%s\nPending: bash %s/admit-pg.sh\nProof: python3 -B %s\nDenial exit=%s\n' "$sha" "$out" "$proof" "$result" > "$out/pending-proof.txt"
fi
exit "$result"
