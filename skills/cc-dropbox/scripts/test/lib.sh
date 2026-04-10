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

# Create an isolated HOME with an empty ~/.config/cc-dropbox directory.
# Sets HOME to the temp dir and returns the path.
make_tmp_home() {
  local tmp
  tmp=$(mktemp -d)
  export HOME="$tmp"
  mkdir -p "$tmp/.config/cc-dropbox"
  echo "$tmp"
}

# Write a credentials.json into the current HOME.
write_creds() {
  local json="$1"
  mkdir -p "$HOME/.config/cc-dropbox"
  printf '%s' "$json" > "$HOME/.config/cc-dropbox/credentials.json"
  chmod 600 "$HOME/.config/cc-dropbox/credentials.json"
}

# Mock curl: responds based on $MOCK_CURL_RESPONSE (body) and
# $MOCK_CURL_HTTP_CODE (default 200). Records the last invocation
# args into $MOCK_CURL_LAST_ARGS for assertions.
# The scripts under test must use:
#   response=$(curl -sS -w '\n%{http_code}' ...)
# so the mock appends http_code on a new line too.
mock_curl() {
  curl() {
    MOCK_CURL_LAST_ARGS="$*"
    local code="${MOCK_CURL_HTTP_CODE:-200}"
    printf '%s\n%s' "${MOCK_CURL_RESPONSE:-}" "$code"
  }
  export -f curl
}

unmock_curl() {
  unset -f curl 2>/dev/null || true
}
