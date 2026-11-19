#!/usr/bin/env bash
# Runs the unit tests. Prints failures and the summary only; the full log goes to build/logs/test.log.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
LOG=build/logs/test.log

swift test >"$LOG" 2>&1
STATUS=$?
grep -E "error:|✘|Test run with" "$LOG" | tail -40
[[ $STATUS -eq 0 ]] || echo "Tests failed. Full log: $LOG"
exit $STATUS
