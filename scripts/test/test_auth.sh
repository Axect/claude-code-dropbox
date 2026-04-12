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

# --- case: expired token triggers refresh ---
make_tmp_home >/dev/null
past=$(( $(date +%s) - 100 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='{"access_token":"fresh_token","expires_in":14400,"token_type":"bearer"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
out=$(
  source "$AUTH_SH"
  get_access_token
) || code=$?

assert_exit_code 0 "$code" "refresh returns 0"
assert_eq "fresh_token" "$out" "returns new access token"

# Verify credentials.json was updated.
new_token=$(jq -r '.access_token' "$HOME/.config/dropbox-skill/credentials.json")
assert_eq "fresh_token" "$new_token" "credentials.json updated"

new_exp=$(jq -r '.access_token_expires_at' "$HOME/.config/dropbox-skill/credentials.json")
now=$(date +%s)
if (( new_exp > now + 14000 && new_exp < now + 14500 )); then
  _pass
else
  _fail "expires_at not in expected window: $new_exp (now=$now)"
fi
unmock_curl

# --- case: refresh returns invalid_grant ---
make_tmp_home >/dev/null
past=$(( $(date +%s) - 100 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='{"error":"invalid_grant","error_description":"refresh token is invalid"}'
MOCK_CURL_HTTP_CODE=400
mock_curl

code=0
(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err || code=$?

assert_exit_code 3 "$code" "invalid_grant exits 3"
assert_contains "$(cat /tmp/cc_err)" "Re-run setup.sh" "error guides user"
unmock_curl

# --- case: api_call success ---
MOCK_CURL_RESPONSE='{"ok":true,"value":42}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
out=$(
  source "$AUTH_SH"
  api_call "https://api.dropboxapi.com/2/some/endpoint" \
           '{"k":"v"}' "TESTTOKEN"
) || code=$?
assert_exit_code 0 "$code" "api_call 200 returns 0"
assert_contains "$out" '"value":42' "returns body"

# --- case: api_call non-2xx ---
MOCK_CURL_RESPONSE='{"error_summary":"path/not_found/"}'
MOCK_CURL_HTTP_CODE=409
mock_curl

code=0
(
  source "$AUTH_SH"
  api_call "https://api.dropboxapi.com/2/x" '{}' "T"
) >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 5 "$code" "non-2xx exits 5 by default"
assert_contains "$(cat /tmp/cc_err)" "path/not_found" "dumps raw body"
unmock_curl

# --- case: refresh returns HTTP 200 but malformed/missing fields ---
make_tmp_home >/dev/null
past=$(( $(date +%s) - 100 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='{"not_a_token":"oops"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err || code=$?

assert_exit_code 5 "$code" "malformed 200 response exits 5"
assert_contains "$(cat /tmp/cc_err)" "missing required fields" "error names the problem"

# Verify credentials.json is unchanged (still has old access_token and past expires_at).
preserved_token=$(jq -r '.access_token' "$HOME/.config/dropbox-skill/credentials.json")
assert_eq "old" "$preserved_token" "credentials.json access_token untouched"
preserved_exp=$(jq -r '.access_token_expires_at' "$HOME/.config/dropbox-skill/credentials.json")
assert_eq "$past" "$preserved_exp" "credentials.json expires_at untouched"
unmock_curl

# --- case: refresh returns HTTP 200 with non-JSON body ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='<html>Captive portal login required</html>'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err || code=$?

assert_exit_code 5 "$code" "non-JSON 200 response exits 5"
assert_contains "$(cat /tmp/cc_err)" "not valid JSON" "error names non-JSON"
preserved_token=$(jq -r '.access_token' "$HOME/.config/dropbox-skill/credentials.json")
assert_eq "old" "$preserved_token" "non-JSON case: access_token untouched"
unmock_curl
