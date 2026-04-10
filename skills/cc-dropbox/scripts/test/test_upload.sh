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
