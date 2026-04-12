# shellcheck shell=bash
TEST_NAME="setup"

SETUP_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup.sh"

# --- case: exchange_code writes a valid credentials.json ---
make_tmp_home >/dev/null

MOCK_CURL_RESPONSE='{"access_token":"AT","refresh_token":"RT","expires_in":14400}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
(
  source "$SETUP_SH"
  exchange_code "app_k" "app_s" "the_code"
) || code=$?
assert_exit_code 0 "$code" "exchange_code returns 0"

creds="$HOME/.config/dropbox-skill/credentials.json"
if [[ -f "$creds" ]]; then _pass; else _fail "credentials.json not created"; fi
assert_eq "app_k" "$(jq -r .app_key "$creds")" "app_key stored"
assert_eq "app_s" "$(jq -r .app_secret "$creds")" "app_secret stored"
assert_eq "RT" "$(jq -r .refresh_token "$creds")" "refresh_token stored"
assert_eq "AT" "$(jq -r .access_token "$creds")" "access_token stored"
perm=$(stat -c %a "$creds")
assert_eq "600" "$perm" "credentials.json is chmod 600"
unmock_curl

# --- case: exchange_code rejects non-2xx responses ---
make_tmp_home >/dev/null
MOCK_CURL_RESPONSE='{"error":"invalid_grant","error_description":"bad code"}'
MOCK_CURL_HTTP_CODE=400
mock_curl

code=0
(
  source "$SETUP_SH"
  exchange_code "k" "s" "bad_code"
) >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "non-2xx exits 1"
assert_contains "$(cat /tmp/cc_err)" "token exchange failed" "error names failure"
if [[ ! -f "$HOME/.config/dropbox-skill/credentials.json" ]]; then _pass; else _fail "credentials.json should NOT be created on failure"; fi
unmock_curl

# --- case: exchange_code validates response has required fields ---
make_tmp_home >/dev/null
MOCK_CURL_RESPONSE='{"not_what_we_want":true}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
(
  source "$SETUP_SH"
  exchange_code "k" "s" "code"
) >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "malformed 200 exits 1"
assert_contains "$(cat /tmp/cc_err)" "missing required fields" "error names missing fields"
if [[ ! -f "$HOME/.config/dropbox-skill/credentials.json" ]]; then _pass; else _fail "credentials.json should NOT be created on malformed"; fi
unmock_curl
