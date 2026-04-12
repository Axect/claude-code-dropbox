#!/usr/bin/env bash
# Manual end-to-end test against a real Dropbox account.
# Run with: DROPBOX_INTEGRATION_TEST=1 bash integration.sh
# Requires an already-configured ~/.config/dropbox-skill/credentials.json.
set -euo pipefail

if [[ "${DROPBOX_INTEGRATION_TEST:-}" != "1" ]]; then
  echo "Refusing to run without DROPBOX_INTEGRATION_TEST=1" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REMOTE_DIR="/dropbox-skill-test-$(date +%s)"
SMALL="$REMOTE_DIR/small.bin"
BIG="$REMOTE_DIR/big.bin"

cleanup() {
  echo "--- cleanup ---"
  # shellcheck source=../auth.sh
  source "$SCRIPT_DIR/auth.sh"
  local token
  token=$(get_access_token) || return 0
  for path in "$SMALL" "$BIG"; do
    curl -sS -X POST "https://api.dropboxapi.com/2/files/delete_v2" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      --data "$(jq -nc --arg p "$path" '{path:$p}')" >/dev/null || true
  done
}
trap 'cleanup' EXIT

echo "--- small file upload/download roundtrip ---"
tmp=$(mktemp)
printf 'hello integration test\n' > "$tmp"
local_hash=$(sha256sum "$tmp" | awk '{print $1}')
bash "$SCRIPT_DIR/upload.sh" "$tmp" "$SMALL"

dest=$(mktemp -u)
bash "$SCRIPT_DIR/download.sh" "$SMALL" "$dest"
dl_hash=$(sha256sum "$dest" | awk '{print $1}')
[[ "$local_hash" == "$dl_hash" ]] || { echo "hash mismatch"; exit 1; }
echo "roundtrip OK"

echo "--- shared link ---"
url=$(bash "$SCRIPT_DIR/share.sh" "$SMALL")
echo "URL: $url"
code=$(curl -sS -o /dev/null -w '%{http_code}' -I "$url")
[[ "$code" == "200" ]] || { echo "share URL returned $code"; exit 1; }

echo "--- shared link reuse (second call) ---"
url2=$(bash "$SCRIPT_DIR/share.sh" "$SMALL")
[[ "$url" == "$url2" ]] || { echo "URL changed on reuse: $url vs $url2"; exit 1; }

echo "--- chunked upload (200 MB) ---"
big_local=$(mktemp)
dd if=/dev/urandom of="$big_local" bs=1M count=200 status=none
bash "$SCRIPT_DIR/upload.sh" "$big_local" "$BIG"

echo "--- ALL INTEGRATION TESTS PASSED ---"
rm -f "$tmp" "$dest" "$big_local"
