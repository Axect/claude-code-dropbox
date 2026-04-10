#!/usr/bin/env bash
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOTAL_PASS=0
TOTAL_FAIL=0

shopt -s nullglob
for test_file in "$TEST_DIR"/test_*.sh; do
  echo "=== $(basename "$test_file") ==="
  # Run in subshell to isolate exports/HOME/etc.
  output=$(bash -c "
    source '$TEST_DIR/lib.sh'
    source '$test_file'
    echo \"__PASS__:\$TEST_PASS\"
    echo \"__FAIL__:\$TEST_FAIL\"
  " 2>&1) || true
  # Extract counters
  pass=$(echo "$output" | awk -F: '/^__PASS__:/{print $2}' | tail -1)
  fail=$(echo "$output" | awk -F: '/^__FAIL__:/{print $2}' | tail -1)
  pass=${pass:-0}
  fail=${fail:-0}
  # Print anything that isn't a counter line
  echo "$output" | grep -v '^__PASS__:\|^__FAIL__:' || true
  echo "  pass=$pass fail=$fail"
  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))
done

echo "---"
echo "TOTAL: pass=$TOTAL_PASS fail=$TOTAL_FAIL"
[[ "$TOTAL_FAIL" -eq 0 ]]
