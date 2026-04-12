#!/usr/bin/env bash
# dropbox-skill upload: upload a local file to Dropbox.
# Usage: upload.sh <local_path> <dropbox_path>
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

CHUNK_THRESHOLD="${DROPBOX_SKILL_CHUNK_THRESHOLD:-${CC_DROPBOX_CHUNK_THRESHOLD:-$((150 * 1024 * 1024))}}"
CHUNK_SIZE="${DROPBOX_SKILL_CHUNK_SIZE:-${CC_DROPBOX_CHUNK_SIZE:-$((8 * 1024 * 1024))}}"

usage() {
  echo "Usage: upload.sh <local_path> <dropbox_path>" >&2
  exit 64
}

[[ $# -eq 2 ]] || usage
LOCAL="$1"
REMOTE="$2"

if [[ "${REMOTE:0:1}" != "/" ]]; then
  echo "dropbox-skill: dropbox path must start with '/': $REMOTE" >&2
  exit 1
fi
if [[ ! -r "$LOCAL" ]]; then
  echo "dropbox-skill: Cannot read local file: $LOCAL" >&2
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
    echo "dropbox-skill: upload failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  printf '%s' "$body" | jq -c '{path:.path_display, size, content_hash}'
}

chunked_upload() {
  local total_chunks=$(( (SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
  local offset=0 session_id="" idx=0
  local response http_code body arg
  local chunk_file
  chunk_file=$(mktemp)
  trap 'rm -f "$chunk_file"' RETURN

  # --- start: first chunk ---
  idx=1
  echo "[$idx/$total_chunks] uploading chunk..." >&2
  arg=$(jq -nc '{close:false}')
  dd if="$LOCAL" bs="$CHUNK_SIZE" skip=0 count=1 status=none > "$chunk_file"
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://content.dropboxapi.com/2/files/upload_session/start" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Dropbox-API-Arg: $arg" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$chunk_file")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [[ "$http_code" != "200" ]]; then
    echo "dropbox-skill: upload_session/start failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  session_id=$(printf '%s' "$body" | jq -r '.session_id')
  offset=$(( CHUNK_SIZE < SIZE ? CHUNK_SIZE : SIZE ))

  # --- append middle chunks ---
  while (( offset < SIZE )); do
    local remaining=$(( SIZE - offset ))
    if (( remaining <= CHUNK_SIZE )); then
      break   # last chunk goes via finish
    fi
    idx=$((idx + 1))
    echo "[$idx/$total_chunks] uploading chunk..." >&2
    arg=$(jq -nc \
      --arg sid "$session_id" \
      --argjson off "$offset" \
      '{cursor:{session_id:$sid, offset:$off}, close:false}')
    local skip=$(( offset / CHUNK_SIZE ))
    dd if="$LOCAL" bs="$CHUNK_SIZE" skip="$skip" count=1 status=none > "$chunk_file"
    response=$(curl -sS -w $'\n%{http_code}' \
      -X POST "https://content.dropboxapi.com/2/files/upload_session/append_v2" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Dropbox-API-Arg: $arg" \
      -H "Content-Type: application/octet-stream" \
      --data-binary "@$chunk_file")
    http_code=$(printf '%s' "$response" | tail -n1)
    body=$(printf '%s' "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
      echo "dropbox-skill: upload_session/append_v2 failed (HTTP $http_code): $body" >&2
      exit 5
    fi
    offset=$(( offset + CHUNK_SIZE ))
  done

  # --- finish: last chunk + commit ---
  idx=$((idx + 1))
  echo "[$idx/$total_chunks] uploading chunk..." >&2
  arg=$(jq -nc \
    --arg sid "$session_id" \
    --argjson off "$offset" \
    --arg path "$REMOTE" \
    '{cursor:{session_id:$sid, offset:$off},
      commit:{path:$path, mode:"overwrite", autorename:false, mute:false}}')
  local skip=$(( offset / CHUNK_SIZE ))
  dd if="$LOCAL" bs="$CHUNK_SIZE" skip="$skip" count=1 status=none > "$chunk_file"
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://content.dropboxapi.com/2/files/upload_session/finish" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Dropbox-API-Arg: $arg" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$chunk_file")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [[ "$http_code" != "200" ]]; then
    echo "dropbox-skill: upload_session/finish failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  printf '%s' "$body" | jq -c '{path:.path_display, size, content_hash}'
}

if (( SIZE <= CHUNK_THRESHOLD )); then
  single_shot_upload
else
  chunked_upload
fi
