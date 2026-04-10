# shellcheck shell=bash
TEST_NAME="auth"

AUTH_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/auth.sh"

# --- case: credentials.json missing ---
make_tmp_home >/dev/null

code=0
(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err || code=$?

assert_exit_code 2 "$code" "missing creds should exit 2"
assert_contains "$(cat /tmp/cc_err)" "setup.sh" "error mentions setup.sh"

# --- case: cached token still valid ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"cached_token\",\"access_token_expires_at\":$future
}"

# Mock curl — should NOT be called in this case.
MOCK_CURL_RESPONSE='{"error":"should_not_be_called"}'
MOCK_CURL_HTTP_CODE=500
mock_curl

code=0
out=$(
  source "$AUTH_SH"
  get_access_token
) || code=$?

assert_exit_code 0 "$code" "cached path returns 0"
assert_eq "cached_token" "$out" "returns cached token"
unmock_curl
