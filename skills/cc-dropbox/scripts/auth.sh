# shellcheck shell=bash
# Sourceable library. Provides: get_access_token, api_call.

# CC_DROPBOX_CREDS: override credentials path (used by tests and for multi-account setups).
CC_DROPBOX_CREDS="${CC_DROPBOX_CREDS:-$HOME/.config/cc-dropbox/credentials.json}"

get_access_token() {
  if [[ ! -f "$CC_DROPBOX_CREDS" ]]; then
    echo "cc-dropbox: no credentials. Run setup.sh first." >&2
    return 2
  fi

  local now access_token expires_at
  now=$(date +%s)
  access_token=$(jq -r '.access_token // ""' "$CC_DROPBOX_CREDS")
  expires_at=$(jq -r '.access_token_expires_at // 0' "$CC_DROPBOX_CREDS")

  if [[ -n "$access_token" && "$expires_at" -gt "$((now + 60))" ]]; then
    printf '%s' "$access_token"
    return 0
  fi

  # Refresh the access token.
  local app_key app_secret refresh_token
  app_key=$(jq -r '.app_key' "$CC_DROPBOX_CREDS")
  app_secret=$(jq -r '.app_secret' "$CC_DROPBOX_CREDS")
  refresh_token=$(jq -r '.refresh_token' "$CC_DROPBOX_CREDS")

  local response body http_code
  # TODO(security): client_secret is passed via curl argv and is briefly visible
  # in /proc/<pid>/cmdline on multi-user systems. Acceptable trade-off for a
  # personal-use plugin; if multi-user support is added, pipe credentials via
  # stdin instead. Same trade-off in setup.sh exchange_code.
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://api.dropboxapi.com/oauth2/token" \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$refresh_token" \
    -d "client_id=$app_key" \
    -d "client_secret=$app_secret")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    if printf '%s' "$body" | jq -e '.error == "invalid_grant"' >/dev/null 2>&1; then
      echo "cc-dropbox: refresh token rejected. Re-run setup.sh." >&2
      return 3
    fi
    echo "cc-dropbox: refresh failed (HTTP $http_code): $body" >&2
    return 5
  fi

  if ! printf '%s' "$body" | jq empty >/dev/null 2>&1; then
    echo "cc-dropbox: refresh response is not valid JSON: $body" >&2
    return 5
  fi

  local new_access new_expires_in new_expires_at
  new_access=$(printf '%s' "$body" | jq -r '.access_token')
  new_expires_in=$(printf '%s' "$body" | jq -r '.expires_in')

  if [[ -z "$new_access" || "$new_access" == "null" \
     || -z "$new_expires_in" || "$new_expires_in" == "null" \
     || ! "$new_expires_in" =~ ^[0-9]+$ ]]; then
    echo "cc-dropbox: refresh response missing required fields" >&2
    return 5
  fi

  new_expires_at=$(( now + new_expires_in ))

  local tmp
  tmp=$(mktemp "${CC_DROPBOX_CREDS}.XXXXXX")
  if ! jq --arg tok "$new_access" --argjson exp "$new_expires_at" \
       '.access_token = $tok | .access_token_expires_at = $exp' \
       "$CC_DROPBOX_CREDS" > "$tmp"; then
    rm -f "$tmp"
    echo "cc-dropbox: failed to update credentials.json" >&2
    return 5
  fi
  mv "$tmp" "$CC_DROPBOX_CREDS"
  chmod 600 "$CC_DROPBOX_CREDS"

  printf '%s' "$new_access"
  return 0
}

# api_call <url> <json_body> <bearer_token>
# On 2xx: echoes response body to stdout, returns 0.
# On non-2xx: dumps "API error (HTTP <code>): <body>" to stderr, returns 5.
#
# Callers that need to branch on specific 409 error_summary values
# (e.g. share.sh distinguishing shared_link_already_exists from path/not_found)
# must call curl directly rather than via this helper.
api_call() {
  local url="$1" body="$2" token="$3"
  local response http_code resp_body
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "$url" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --data "$body")
  http_code=$(printf '%s' "$response" | tail -n1)
  resp_body=$(printf '%s' "$response" | sed '$d')

  if [[ "$http_code" =~ ^2 ]]; then
    printf '%s' "$resp_body"
    return 0
  fi
  echo "cc-dropbox: API error (HTTP $http_code): $resp_body" >&2
  return 5
}
