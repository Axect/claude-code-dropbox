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

# --- case: shared_link_already_exists → list_shared_links fallback ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Two-call mock using the temp-file counter pattern from Batch 4.
mock_curl_share_reuse() {
  MOCK_CURL_CALL_FILE=$(mktemp)
  export MOCK_CURL_CALL_FILE
  printf '0' > "$MOCK_CURL_CALL_FILE"
  curl() {
    local n
    n=$(cat "$MOCK_CURL_CALL_FILE")
    n=$((n + 1))
    printf '%s' "$n" > "$MOCK_CURL_CALL_FILE"
    case "$n" in
      1) printf '%s\n%s' '{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}' '409' ;;
      2) printf '%s\n%s' '{"links":[{"url":"https://www.dropbox.com/s/existing/file.txt?dl=0"}],"has_more":false}' '200' ;;
      *) printf '%s\n%s' '{}' '500' ;;
    esac
  }
  export -f curl
}
mock_curl_share_reuse

code=0
out=$(bash "$SHARE_SH" "/remote/file.txt") || code=$?
assert_exit_code 0 "$code" "reuse returns 0"
assert_eq "https://www.dropbox.com/s/existing/file.txt?dl=0" "$out" "returns existing URL"
assert_eq "2" "$(cat "$MOCK_CURL_CALL_FILE")" "made exactly 2 curl calls"
unmock_curl

# --- case: generic 409 error (neither path/not_found nor already_exists) ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

MOCK_CURL_RESPONSE='{"error_summary":"email_not_verified/..","error":{".tag":"email_not_verified"}}'
MOCK_CURL_HTTP_CODE=409
mock_curl

code=0
(bash "$SHARE_SH" "/remote/file.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 5 "$code" "generic 409 exits 5"
assert_contains "$(cat /tmp/cc_err)" "HTTP 409" "error names HTTP code"
assert_contains "$(cat /tmp/cc_err)" "email_not_verified" "error dumps body"
unmock_curl

# --- case: list_shared_links HTTP failure during reuse fallback ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Two-call mock: call 1 returns 409 shared_link_already_exists, call 2 returns 500.
mock_curl_share_list_fail() {
  MOCK_CURL_CALL_FILE=$(mktemp)
  export MOCK_CURL_CALL_FILE
  printf '0' > "$MOCK_CURL_CALL_FILE"
  curl() {
    local n
    n=$(cat "$MOCK_CURL_CALL_FILE")
    n=$((n + 1))
    printf '%s' "$n" > "$MOCK_CURL_CALL_FILE"
    case "$n" in
      1) printf '%s\n%s' '{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}' '409' ;;
      2) printf '%s\n%s' '{"error_summary":"internal_error"}' '500' ;;
      *) printf '%s\n%s' '{}' '500' ;;
    esac
  }
  export -f curl
}
mock_curl_share_list_fail

code=0
(bash "$SHARE_SH" "/remote/file.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 5 "$code" "list_shared_links 500 exits 5"
assert_contains "$(cat /tmp/cc_err)" "list_shared_links failed" "error names failing endpoint"
assert_eq "2" "$(cat "$MOCK_CURL_CALL_FILE")" "made exactly 2 curl calls"
unmock_curl
