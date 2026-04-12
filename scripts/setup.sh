#!/usr/bin/env bash
# dropbox-skill setup: interactive OAuth2 bootstrap.
# Sourceable for tests: defines exchange_code(). If executed directly, runs
# the interactive flow at the bottom.

set -uo pipefail

# DROPBOX_SKILL_CREDS: override credentials path (used by tests and for multi-account setups).
# Intentionally duplicated from auth.sh — setup.sh must not source auth.sh so
# that setup can run on a fresh install with no credentials file present.
DROPBOX_SKILL_CREDS="${DROPBOX_SKILL_CREDS:-$HOME/.config/dropbox-skill/credentials.json}"
LEGACY_CC_DROPBOX_CREDS="${CC_DROPBOX_CREDS:-$HOME/.config/cc-dropbox/credentials.json}"
if [[ -z "${DROPBOX_SKILL_CREDS_EXPLICIT:-}" && ! -f "$DROPBOX_SKILL_CREDS" && -f "$LEGACY_CC_DROPBOX_CREDS" ]]; then
  DROPBOX_SKILL_CREDS="$LEGACY_CC_DROPBOX_CREDS"
fi

require_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "dropbox-skill: '$cmd' is required but not found." >&2
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
  # TODO(security): client_secret is passed via curl argv and is briefly visible
  # in /proc/<pid>/cmdline on multi-user systems. Acceptable trade-off for a
  # personal-use skill; if multi-user support is added, pipe credentials via
  # stdin instead. Same trade-off in auth.sh refresh path.
  response=$(curl -sS -w $'\n%{http_code}' \
    -X POST "https://api.dropboxapi.com/oauth2/token" \
    -d "grant_type=authorization_code" \
    -d "code=$code" \
    -d "client_id=$app_key" \
    -d "client_secret=$app_secret")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "dropbox-skill: token exchange failed (HTTP $http_code): $body" >&2
    return 1
  fi

  if ! printf '%s' "$body" | jq empty >/dev/null 2>&1; then
    echo "dropbox-skill: token exchange response is not valid JSON: $body" >&2
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
    echo "dropbox-skill: token exchange response missing required fields" >&2
    return 1
  fi

  local now expires_at
  now=$(date +%s)
  expires_at=$(( now + expires_in ))

  mkdir -p "$(dirname "$DROPBOX_SKILL_CREDS")"
  local tmp
  tmp=$(mktemp "${DROPBOX_SKILL_CREDS}.XXXXXX")
  if ! jq -n \
      --arg ak "$app_key" \
      --arg as "$app_secret" \
      --arg rt "$refresh" \
      --arg at "$access" \
      --argjson exp "$expires_at" \
      '{app_key:$ak, app_secret:$as, refresh_token:$rt, access_token:$at, access_token_expires_at:$exp}' \
      > "$tmp"; then
    rm -f "$tmp"
    echo "dropbox-skill: failed to write credentials.json" >&2
    return 1
  fi
  if ! mv "$tmp" "$DROPBOX_SKILL_CREDS"; then
    rm -f "$tmp"
    echo "dropbox-skill: failed to install credentials.json" >&2
    return 1
  fi
  chmod 600 "$DROPBOX_SKILL_CREDS" || \
    echo "dropbox-skill: warning: chmod 600 failed on $DROPBOX_SKILL_CREDS" >&2
  return 0
}

run_interactive() {
  require_deps

  echo "=== dropbox-skill setup ==="
  echo
  echo "1. Go to https://www.dropbox.com/developers/apps and create (or open) your app."
  echo "   - Permission type: Scoped access"
  echo "   - Access type: Full Dropbox"
  echo "   - In the Permissions tab, enable:"
  echo "       files.content.write, files.content.read, sharing.write, sharing.read"
  echo "   - Submit the permissions."
  echo
  read -r -p "App key: " APP_KEY
  [[ -z "$APP_KEY" ]] && { echo "dropbox-skill: app key is required" >&2; exit 1; }
  read -r -s -p "App secret (hidden): " APP_SECRET; echo
  [[ -z "$APP_SECRET" ]] && { echo "dropbox-skill: app secret is required" >&2; exit 1; }
  echo
  echo "2. Open this URL in a browser and approve access:"
  echo
  echo "   https://www.dropbox.com/oauth2/authorize?client_id=${APP_KEY}&response_type=code&token_access_type=offline"
  echo
  echo "   After approving, Dropbox will display an authorization code. Copy it."
  echo
  read -r -p "Paste the authorization code: " AUTH_CODE
  [[ -z "$AUTH_CODE" ]] && { echo "dropbox-skill: authorization code is required" >&2; exit 1; }

  if exchange_code "$APP_KEY" "$APP_SECRET" "$AUTH_CODE"; then
    echo
    echo "✓ Setup complete. Credentials saved to $DROPBOX_SKILL_CREDS"
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
