# shellcheck shell=bash
TEST_NAME="share"

SHARE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/share.sh"

# --- case: create_shared_link_with_settings returns 200 ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

MOCK_CURL_RESPONSE='{"url":"https://www.dropbox.com/scl/fi/abc/file.txt?dl=0","id":"id:xxx"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
out=$(bash "$SHARE_SH" "/remote/file.txt") || code=$?
assert_exit_code 0 "$code" "share returns 0"
assert_eq "https://www.dropbox.com/scl/fi/abc/file.txt?dl=0" "$out" "prints URL"
unmock_curl

# --- case: path_not_found ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
MOCK_CURL_RESPONSE='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}'
MOCK_CURL_HTTP_CODE=409
mock_curl

code=0
(bash "$SHARE_SH" "/missing.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 4 "$code" "not_found exits 4"
assert_contains "$(cat /tmp/cc_err)" "Not found" "error mentions not found"
unmock_curl

# --- case: relative dropbox path is rejected ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
code=0
(bash "$SHARE_SH" "relative/path.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "relative path exits 1"
assert_contains "$(cat /tmp/cc_err)" "must start with '/'" "error mentions leading slash"
