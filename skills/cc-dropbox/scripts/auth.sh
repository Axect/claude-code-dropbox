# shellcheck shell=bash
# Sourceable library. Provides: get_access_token, api_call.

CC_DROPBOX_CREDS="${CC_DROPBOX_CREDS:-$HOME/.config/cc-dropbox/credentials.json}"

get_access_token() {
  if [[ ! -f "$CC_DROPBOX_CREDS" ]]; then
    echo "cc-dropbox: no credentials. Run setup.sh first." >&2
    return 2
  fi
  # Minimal stub to be filled in subsequent tasks.
  return 99
}
