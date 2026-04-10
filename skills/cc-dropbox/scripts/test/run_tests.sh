#!/usr/bin/env bash
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOTAL_PASS=0
TOTAL_FAIL=0

shopt -s nullglob
for test_file in "$TEST_DIR"/test_*.sh; do
  echo "=== $(basename "$test_file") ==="
  output=$(bash -c "
    set -eo pipefail
    source '$TEST_DIR/lib.sh'
    source '$test_file'
    echo \"__PASS__:\$TEST_PASS\"
    echo \"__FAIL__:\$TEST_FAIL\"
  " 2>&1) || true

  pass=$(echo "$output" | awk -F: '$1=="__PASS__"{print $2}' | tail -1)
  fail=$(echo "$output" | awk -F: '$1=="__FAIL__"{print $2}' | tail -1)

  # Anything not a counter line is noise we want to surface.
  echo "$output" | grep -Ev '^(__PASS__|__FAIL__):' || true

  if [[ -z "$pass" || -z "$fail" ]]; then
    echo "  ERROR: test file did not report counters (aborted early?)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    continue
  fi

  echo "  pass=$pass fail=$fail"
  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))
done

echo "---"
echo "TOTAL: pass=$TOTAL_PASS fail=$TOTAL_FAIL"
[[ "$TOTAL_FAIL" -eq 0 ]]
