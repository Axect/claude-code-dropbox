#!/usr/bin/env bash
# cc-dropbox download: fetch a file from Dropbox.
# Usage: download.sh <dropbox_path> [<local_path>]
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

usage() {
  echo "Usage: download.sh <dropbox_path> [<local_path>]" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
REMOTE="$1"
LOCAL="${2:-}"

if [[ "${REMOTE:0:1}" != "/" ]]; then
  echo "cc-dropbox: dropbox path must start with '/': $REMOTE" >&2
  exit 1
fi

if [[ -z "$LOCAL" ]]; then
  LOCAL="$(basename "$REMOTE")"
fi

# -e misses dangling symlinks; -L catches any symlink (dangling or not).
# Refuse if the destination exists OR is a symlink, to avoid curl --output
# following a planted symlink to an unintended target.
if [[ -e "$LOCAL" || -L "$LOCAL" ]]; then
  echo "cc-dropbox: File exists: $LOCAL. Remove it or specify a different destination." >&2
  exit 1
fi

parent_dir=$(dirname "$LOCAL")
if [[ ! -d "$parent_dir" ]]; then
  echo "cc-dropbox: parent directory does not exist: $parent_dir" >&2
  exit 1
fi

TOKEN=$(get_access_token) || exit $?

arg=$(jq -nc --arg path "$REMOTE" '{path:$path}')
curl_rc=0
response=$(curl -sS -w $'\n%{http_code}' \
  -X POST "https://content.dropboxapi.com/2/files/download" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Dropbox-API-Arg: $arg" \
  --output "$LOCAL") || curl_rc=$?
if [[ $curl_rc -ne 0 ]]; then
  rm -f "$LOCAL"
  echo "cc-dropbox: curl failed (exit $curl_rc) writing to $LOCAL" >&2
  exit "$curl_rc"
fi
http_code=$(printf '%s' "$response" | tail -n1)

if [[ "$http_code" == "200" ]]; then
  printf '%s\n' "$LOCAL"
  exit 0
fi

# On non-200, Dropbox wrote an error JSON to the output file. Read and clean up.
if [[ -f "$LOCAL" ]]; then
  err_body=$(cat "$LOCAL")
  rm -f "$LOCAL"
else
  err_body=""
fi

if [[ "$http_code" == "409" ]] && printf '%s' "$err_body" | jq -e '.error_summary | startswith("path/not_found")' >/dev/null 2>&1; then
  echo "cc-dropbox: Not found: $REMOTE" >&2
  exit 4
fi

echo "cc-dropbox: download failed (HTTP $http_code): $err_body" >&2
exit 5
