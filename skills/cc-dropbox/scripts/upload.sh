#!/usr/bin/env bash
# cc-dropbox upload: upload a local file to Dropbox.
# Usage: upload.sh <local_path> <dropbox_path>
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

CHUNK_THRESHOLD="${CC_DROPBOX_CHUNK_THRESHOLD:-$((150 * 1024 * 1024))}"
CHUNK_SIZE="${CC_DROPBOX_CHUNK_SIZE:-$((8 * 1024 * 1024))}"

usage() {
  echo "Usage: upload.sh <local_path> <dropbox_path>" >&2
  exit 64
}

[[ $# -eq 2 ]] || usage
LOCAL="$1"
REMOTE="$2"

if [[ "${REMOTE:0:1}" != "/" ]]; then
  echo "cc-dropbox: dropbox path must start with '/': $REMOTE" >&2
  exit 1
fi
if [[ ! -r "$LOCAL" ]]; then
  echo "cc-dropbox: Cannot read local file: $LOCAL" >&2
  exit 1
fi

TOKEN=$(get_access_token) || exit $?
SIZE=$(stat -c %s "$LOCAL")

single_shot_upload() {
  local arg
  arg=$(jq -nc \
    --arg path "$REMOTE" \
    '{path:$path, mode:"overwrite", autorename:false, mute:false}')
  local response http_code body
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://content.dropboxapi.com/2/files/upload" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Dropbox-API-Arg: $arg" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$LOCAL")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [[ "$http_code" != "200" ]]; then
    echo "cc-dropbox: upload failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  printf '%s' "$body" | jq -c '{path:.path_display, size, content_hash}'
}

chunked_upload() {
  echo "cc-dropbox: chunked upload implemented in Task 10." >&2
  exit 99
}

if (( SIZE <= CHUNK_THRESHOLD )); then
  single_shot_upload
else
  chunked_upload
fi
