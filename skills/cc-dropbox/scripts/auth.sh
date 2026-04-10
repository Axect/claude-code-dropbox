# shellcheck shell=bash
# Sourceable library. Provides: get_access_token, api_call.

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

  # Refresh path — implemented in Task 5.
  return 99
}
