# shellcheck shell=bash
TEST_NAME="download"

DL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/download.sh"

# --- case: download writes file to specified local path ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Custom mock: download writes bytes to --output <path>, prints HTTP 200.
mock_curl_download() {
  curl() {
    local out_path=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--output" ]]; then
        out_path="$2"; shift 2
      else
        shift
      fi
    done
    if [[ -n "$out_path" ]]; then
      printf 'dropbox body content' > "$out_path"
    fi
    printf '%s\n%s' '' '200'
  }
  export -f curl
}
mock_curl_download

dest=$(mktemp -u)
code=0
out=$(bash "$DL_SH" "/remote/file.txt" "$dest") || code=$?
assert_exit_code 0 "$code" "download returns 0"
if [[ -f "$dest" ]]; then _pass; else _fail "dest file not created"; fi
assert_eq "dropbox body content" "$(cat "$dest")" "content written"
assert_eq "$dest" "$out" "prints saved path"
rm -f "$dest"
unmock_curl

# --- case: refuses to overwrite existing local file ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
existing=$(mktemp)
echo "do not clobber" > "$existing"
code=0
(bash "$DL_SH" "/remote/file.txt" "$existing") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "existing file exits 1"
assert_contains "$(cat /tmp/cc_err)" "File exists" "error mentions exists"
assert_eq "do not clobber" "$(cat "$existing")" "original untouched"
rm -f "$existing"

# --- case: 404-equivalent from Dropbox (409 path/not_found) ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Mock: writes error JSON to --output, returns HTTP 409.
mock_curl_notfound() {
  curl() {
    local out_path=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--output" ]]; then
        out_path="$2"; shift 2
      else
        shift
      fi
    done
    if [[ -n "$out_path" ]]; then
      printf '%s' '{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}' > "$out_path"
    fi
    printf '%s\n%s' '' '409'
  }
  export -f curl
}
mock_curl_notfound

dest=$(mktemp -u)
code=0
(bash "$DL_SH" "/missing.txt" "$dest") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 4 "$code" "path_not_found exits 4"
assert_contains "$(cat /tmp/cc_err)" "Not found" "error mentions not found"
if [[ ! -f "$dest" ]]; then _pass; else _fail "error file should have been cleaned up"; fi
unmock_curl

# --- case: relative dropbox path is rejected ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
code=0
(bash "$DL_SH" "relative/path.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "relative path exits 1"
assert_contains "$(cat /tmp/cc_err)" "must start with '/'" "error mentions leading slash"

# --- case: default local path (omitted) uses basename of dropbox path in CWD ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

mock_curl_download

scratch=$(mktemp -d)
code=0
out=$(cd "$scratch" && bash "$DL_SH" "/Papers/draft.pdf") || code=$?
assert_exit_code 0 "$code" "default local path returns 0"
assert_eq "draft.pdf" "$out" "prints basename"
if [[ -f "$scratch/draft.pdf" ]]; then _pass; else _fail "file not created at basename in CWD"; fi
assert_eq "dropbox body content" "$(cat "$scratch/draft.pdf")" "content written"
rm -rf "$scratch"
unmock_curl

# --- case: missing parent directory is rejected ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

code=0
(bash "$DL_SH" "/remote/file.txt" "/no/such/dir/file.txt") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "missing parent dir exits 1"
assert_contains "$(cat /tmp/cc_err)" "parent directory does not exist" "error names missing parent"

# --- case: refuse to write through a dangling symlink ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

scratch=$(mktemp -d)
dangling="$scratch/link"
ln -s "$scratch/nonexistent_target" "$dangling"
code=0
(bash "$DL_SH" "/remote/file.txt" "$dangling") >/tmp/cc_out 2>/tmp/cc_err || code=$?
assert_exit_code 1 "$code" "dangling symlink exits 1"
assert_contains "$(cat /tmp/cc_err)" "File exists" "error mentions exists"
if [[ ! -e "$scratch/nonexistent_target" ]]; then _pass; else _fail "dangling symlink target was written through"; fi
rm -rf "$scratch"
