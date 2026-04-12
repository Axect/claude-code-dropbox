# shellcheck shell=bash
TEST_NAME="smoke"

assert_eq "hello" "hello" "string equality"
assert_exit_code 0 0 "zero exit"
assert_contains "the quick brown fox" "quick" "contains quick"
