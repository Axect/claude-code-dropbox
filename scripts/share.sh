#!/usr/bin/env bash
# dropbox-skill share: create or retrieve a shared link for a Dropbox path.
# Usage: share.sh <dropbox_path>
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

usage() {
  echo "Usage: share.sh <dropbox_path>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
REMOTE="$1"

if [[ "${REMOTE:0:1}" != "/" ]]; then
  echo "dropbox-skill: dropbox path must start with '/': $REMOTE" >&2
  exit 1
fi

TOKEN=$(get_access_token) || exit $?

create_body=$(jq -nc --arg p "$REMOTE" '{
  path: $p,
  settings: {
    requested_visibility: "public",
    audience: "public",
    access: "viewer"
  }
}')

response=$(curl -sS -w $'\n%{http_code}' \
  -X POST "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data "$create_body")
http_code=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')

if [[ "$http_code" == "200" ]]; then
  printf '%s' "$body" | jq -r '.url'
  exit 0
fi

if [[ "$http_code" == "409" ]]; then
  summary=$(printf '%s' "$body" | jq -r '.error_summary // ""')
  if [[ "$summary" == path/not_found* ]]; then
    echo "dropbox-skill: Not found: $REMOTE" >&2
    exit 4
  fi
  if [[ "$summary" == shared_link_already_exists* ]]; then
    # direct_only:false — broader match to avoid false "not found" when
    # create_shared_link_with_settings just reported the link exists.
    list_body=$(jq -nc --arg p "$REMOTE" '{path:$p, direct_only:false}')
    response=$(curl -sS -w $'\n%{http_code}' \
      -X POST "https://api.dropboxapi.com/2/sharing/list_shared_links" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$list_body")
    http_code=$(printf '%s' "$response" | tail -n1)
    body=$(printf '%s' "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
      echo "dropbox-skill: list_shared_links failed (HTTP $http_code): $body" >&2
      exit 5
    fi
    url=$(printf '%s' "$body" | jq -r '.links[0].url // ""')
    if [[ -z "$url" ]]; then
      echo "dropbox-skill: no existing shared link found for $REMOTE" >&2
      exit 5
    fi
    printf '%s\n' "$url"
    exit 0
  fi
fi

echo "dropbox-skill: share failed (HTTP $http_code): $body" >&2
exit 5
