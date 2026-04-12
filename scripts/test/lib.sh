# shellcheck shell=bash
# Test helpers shared by all test_*.sh files.

TEST_PASS=0
TEST_FAIL=0
TEST_NAME="${TEST_NAME:-unknown}"

_fail() {
  TEST_FAIL=$((TEST_FAIL + 1))
  echo "  FAIL [$TEST_NAME]: $*" >&2
}

_pass() {
  TEST_PASS=$((TEST_PASS + 1))
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-values differ}"
  if [[ "$expected" == "$actual" ]]; then
    _pass
  else
    _fail "$msg: expected '$expected', got '$actual'"
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-exit code}"
  if [[ "$expected" == "$actual" ]]; then
    _pass
  else
    _fail "$msg: expected $expected, got $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-substring missing}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _pass
  else
    _fail "$msg: '$needle' not in '$haystack'"
  fi
}

# Create an isolated HOME with an empty ~/.config/dropbox-skill directory.
# Cleans up automatically on subshell exit (each test file runs in its
# own subshell courtesy of run_tests.sh). Returns the path on stdout.
make_tmp_home() {
  local tmp
  tmp=$(mktemp -d)
  export HOME="$tmp"
  mkdir -p "$tmp/.config/dropbox-skill"
  trap 'rm -rf "$HOME"' EXIT
  echo "$tmp"
}

# Write a credentials.json into the current HOME.
write_creds() {
  local json="$1"
  mkdir -p "$HOME/.config/dropbox-skill"
  printf '%s' "$json" > "$HOME/.config/dropbox-skill/credentials.json"
  chmod 600 "$HOME/.config/dropbox-skill/credentials.json"
}

# Mock curl: responds based on $MOCK_CURL_RESPONSE (body) and
# $MOCK_CURL_HTTP_CODE (default 200). Records each invocation's args
# (one line per call) to $MOCK_CURL_ARGS_FILE. Tests assert on the
# last-recorded args via last_curl_args.
#
# Scripts under test should use:
#   response=$(curl -sS -w '\n%{http_code}' ...)
# so the mock appends http_code on a new line too.
mock_curl() {
  MOCK_CURL_ARGS_FILE=$(mktemp)
  export MOCK_CURL_ARGS_FILE
  # Export response vars so the mock function works in child bash processes
  # (e.g. when a script under test is invoked via `bash script.sh`).
  export MOCK_CURL_RESPONSE="${MOCK_CURL_RESPONSE:-}"
  export MOCK_CURL_HTTP_CODE="${MOCK_CURL_HTTP_CODE:-200}"
  curl() {
    printf '%s\n' "$*" >> "$MOCK_CURL_ARGS_FILE"
    local code="${MOCK_CURL_HTTP_CODE:-200}"
    printf '%s\n%s' "${MOCK_CURL_RESPONSE:-}" "$code"
  }
  export -f curl
}

unmock_curl() {
  unset -f curl 2>/dev/null || true
  if [[ -n "${MOCK_CURL_ARGS_FILE:-}" && -f "$MOCK_CURL_ARGS_FILE" ]]; then
    rm -f "$MOCK_CURL_ARGS_FILE"
  fi
  unset MOCK_CURL_ARGS_FILE
  if [[ -n "${MOCK_CURL_CALL_FILE:-}" && -f "$MOCK_CURL_CALL_FILE" ]]; then
    rm -f "$MOCK_CURL_CALL_FILE"
  fi
  unset MOCK_CURL_CALL_FILE
}

# Return the last recorded curl invocation's args as a single line.
# Empty string if nothing has been recorded.
last_curl_args() {
  if [[ -n "${MOCK_CURL_ARGS_FILE:-}" && -f "$MOCK_CURL_ARGS_FILE" ]]; then
    tail -n 1 "$MOCK_CURL_ARGS_FILE"
  else
    printf ''
  fi
}
