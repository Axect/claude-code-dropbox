# shellcheck shell=bash
TEST_NAME="upload"

UPLOAD_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/upload.sh"

# --- case: small file single-shot upload ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

tmp_file=$(mktemp)
echo "hello dropbox" > "$tmp_file"

MOCK_CURL_RESPONSE='{"path_display":"/t/hello.txt","size":14,"content_hash":"abc123"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

code=0
out=$(bash "$UPLOAD_SH" "$tmp_file" "/t/hello.txt") || code=$?
assert_exit_code 0 "$code" "upload returns 0"
assert_contains "$out" '"path":"/t/hello.txt"' "summary includes path"
assert_contains "$out" '"size":14' "summary includes size"
assert_contains "$out" '"content_hash":"abc123"' "summary includes hash"
unmock_curl
rm -f "$tmp_file"

# --- case: missing local file ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
code=0
(bash "$UPLOAD_SH" "/no/such/file" "/t/x.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "missing file exits 1"
assert_contains "$(cat /tmp/cc_err)" "Cannot read" "error mentions cannot read"

# --- case: relative dropbox path is rejected ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
tmp_file=$(mktemp)
echo "x" > "$tmp_file"
code=0
(bash "$UPLOAD_SH" "$tmp_file" "relative/path.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "relative path exits 1"
assert_contains "$(cat /tmp/cc_err)" "must start with '/'" "error mentions leading slash"
rm -f "$tmp_file"

# --- case: chunked path is taken when size exceeds threshold ---
# Use CC_DROPBOX_CHUNK_THRESHOLD=10 + CC_DROPBOX_CHUNK_SIZE=8 to force the
# chunked path for a 20-byte file (3 chunks: 8, 8, 4).
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

tmp_file=$(mktemp)
printf '%s' "0123456789ABCDEFGHIJ" > "$tmp_file"   # 20 bytes

# Multi-call mock: start, append, finish.
mock_curl_chunked() {
  # Use a temp file as counter so the state persists even when curl is invoked
  # inside command substitution $(curl ...) subshells.
  export MOCK_CURL_CALL_FILE
  MOCK_CURL_CALL_FILE=$(mktemp)
  printf '0' > "$MOCK_CURL_CALL_FILE"
  curl() {
    local call
    call=$(( $(cat "$MOCK_CURL_CALL_FILE") + 1 ))
    printf '%s' "$call" > "$MOCK_CURL_CALL_FILE"
    case "$call" in
      1) printf '%s\n%s' '{"session_id":"SID"}' '200' ;;
      2) printf '%s\n%s' '{}' '200' ;;
      3) printf '%s\n%s' '{"path_display":"/t/big.bin","size":20,"content_hash":"ZZZ"}' '200' ;;
      *) printf '%s\n%s' '{}' '200' ;;
    esac
  }
  export -f curl
}
mock_curl_chunked

code=0
out=$(
  CC_DROPBOX_CHUNK_THRESHOLD=10 CC_DROPBOX_CHUNK_SIZE=8 \
    bash "$UPLOAD_SH" "$tmp_file" "/t/big.bin"
) || code=$?
assert_exit_code 0 "$code" "chunked returns 0"
assert_contains "$out" '"path":"/t/big.bin"' "chunked summary path"
assert_contains "$out" '"size":20' "chunked summary size"
assert_contains "$out" '"content_hash":"ZZZ"' "chunked summary hash"
assert_eq "3" "$(cat "$MOCK_CURL_CALL_FILE")" "chunked made exactly 3 curl calls"
unmock_curl
rm -f "$tmp_file"

# --- case: chunked upload_session/start returns non-200 ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

tmp_file=$(mktemp)
printf '%s' "0123456789ABCDEFGHIJ" > "$tmp_file"   # 20 bytes

MOCK_CURL_RESPONSE='{"error_summary":"server_error/."}'
MOCK_CURL_HTTP_CODE=500
mock_curl

code=0
(
  CC_DROPBOX_CHUNK_THRESHOLD=10 CC_DROPBOX_CHUNK_SIZE=8 \
    bash "$UPLOAD_SH" "$tmp_file" "/t/big.bin"
) >/tmp/cc_upload_out 2>/tmp/cc_upload_err || code=$?

assert_exit_code 5 "$code" "chunked start failure exits 5"
assert_contains "$(cat /tmp/cc_upload_err)" "upload_session/start failed" "error names failing endpoint"
unmock_curl
rm -f "$tmp_file" /tmp/cc_upload_out /tmp/cc_upload_err
