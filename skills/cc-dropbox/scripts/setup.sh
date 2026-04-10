#!/usr/bin/env bash
# cc-dropbox setup: interactive OAuth2 bootstrap.
# Sourceable for tests: defines exchange_code(). If executed directly, runs
# the interactive flow at the bottom.

set -uo pipefail

# CC_DROPBOX_CREDS: override credentials path (used by tests and for multi-account setups).
CC_DROPBOX_CREDS="${CC_DROPBOX_CREDS:-$HOME/.config/cc-dropbox/credentials.json}"

require_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "cc-dropbox: '$cmd' is required but not found." >&2
      exit 127
    fi
  done
}

# exchange_code <app_key> <app_secret> <auth_code>
# Exchanges an authorization code for an access+refresh token pair and
# writes credentials.json atomically. Returns 0 on success, 1 on failure.
exchange_code() {
  local app_key="$1" app_secret="$2" code="$3"
  local response body http_code
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://api.dropboxapi.com/oauth2/token" \
    -d "grant_type=authorization_code" \
    -d "code=$code" \
    -d "client_id=$app_key" \
    -d "client_secret=$app_secret")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "cc-dropbox: token exchange failed (HTTP $http_code): $body" >&2
    return 1
  fi

  if ! printf '%s' "$body" | jq empty >/dev/null 2>&1; then
    echo "cc-dropbox: token exchange response is not valid JSON: $body" >&2
    return 1
  fi

  local access refresh expires_in
  access=$(printf '%s' "$body" | jq -r '.access_token')
  refresh=$(printf '%s' "$body" | jq -r '.refresh_token')
  expires_in=$(printf '%s' "$body" | jq -r '.expires_in')

  if [[ -z "$access" || "$access" == "null" \
     || -z "$refresh" || "$refresh" == "null" \
     || -z "$expires_in" || "$expires_in" == "null" \
     || ! "$expires_in" =~ ^[0-9]+$ ]]; then
    echo "cc-dropbox: token exchange response missing required fields" >&2
    return 1
  fi

  local now expires_at
  now=$(date +%s)
  expires_at=$(( now + expires_in ))

  mkdir -p "$(dirname "$CC_DROPBOX_CREDS")"
  local tmp
  tmp=$(mktemp "${CC_DROPBOX_CREDS}.XXXXXX")
  if ! jq -n \
      --arg ak "$app_key" \
      --arg as "$app_secret" \
      --arg rt "$refresh" \
      --arg at "$access" \
      --argjson exp "$expires_at" \
      '{app_key:$ak, app_secret:$as, refresh_token:$rt, access_token:$at, access_token_expires_at:$exp}' \
      > "$tmp"; then
    rm -f "$tmp"
    echo "cc-dropbox: failed to write credentials.json" >&2
    return 1
  fi
  mv "$tmp" "$CC_DROPBOX_CREDS"
  chmod 600 "$CC_DROPBOX_CREDS"
}

run_interactive() {
  require_deps

  echo "=== cc-dropbox setup ==="
  echo
  echo "1. Go to https://www.dropbox.com/developers/apps and create (or open) your app."
  echo "   - Permission type: Scoped access"
  echo "   - Access type: Full Dropbox"
  echo "   - In the Permissions tab, enable:"
  echo "       files.content.write, files.content.read, sharing.write, sharing.read"
  echo "   - Submit the permissions."
  echo
  read -r -p "App key: " APP_KEY
  read -r -s -p "App secret (hidden): " APP_SECRET; echo
  echo
  echo "2. Open this URL in a browser and approve access:"
  echo
  echo "   https://www.dropbox.com/oauth2/authorize?client_id=${APP_KEY}&response_type=code&token_access_type=offline"
  echo
  read -r -p "Paste the authorization code: " AUTH_CODE

  if exchange_code "$APP_KEY" "$APP_SECRET" "$AUTH_CODE"; then
    echo
    echo "✓ Setup complete. Credentials saved to $CC_DROPBOX_CREDS"
  else
    echo
    echo "✗ Setup failed." >&2
    exit 1
  fi
}

# If this file is executed (not sourced), run the interactive flow.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_interactive
fi
