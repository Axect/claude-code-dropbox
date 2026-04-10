# shellcheck shell=bash
TEST_NAME="auth"

AUTH_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/auth.sh"

# --- case: credentials.json missing ---
make_tmp_home >/dev/null

code=0
(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err || code=$?

assert_exit_code 2 "$code" "missing creds should exit 2"
assert_contains "$(cat /tmp/cc_err)" "setup.sh" "error mentions setup.sh"
