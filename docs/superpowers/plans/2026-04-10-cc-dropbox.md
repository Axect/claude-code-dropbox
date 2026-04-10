# cc-dropbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that unifies three Dropbox operations (upload, download, shared-link) via bash scripts driven by `SKILL.md`.

**Architecture:** Plugin directory houses `SKILL.md` + independent bash scripts under `skills/cc-dropbox/scripts/`. A sourceable `auth.sh` provides `get_access_token` (refresh-token OAuth2). Each operation script calls the Dropbox HTTP API v2 via `curl`+`jq`. Tests override `curl` as a shell function to inject fixture responses.

**Tech Stack:** bash, curl, jq, coreutils (stat/dd/mktemp). Dropbox HTTP API v2. No other runtime deps.

**Spec:** `docs/superpowers/specs/2026-04-10-cc-dropbox-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | Plugin metadata |
| `skills/cc-dropbox/SKILL.md` | Claude entry point: triggers + usage rules |
| `skills/cc-dropbox/scripts/auth.sh` | Sourceable: `get_access_token`, `api_call` helper, credential I/O |
| `skills/cc-dropbox/scripts/setup.sh` | One-shot OAuth2 bootstrap (interactive) |
| `skills/cc-dropbox/scripts/upload.sh` | Upload local → Dropbox (auto chunked >150MB) |
| `skills/cc-dropbox/scripts/download.sh` | Download Dropbox → local (refuses overwrite) |
| `skills/cc-dropbox/scripts/share.sh` | Create or retrieve shared link |
| `skills/cc-dropbox/scripts/test/run_tests.sh` | Unit test runner |
| `skills/cc-dropbox/scripts/test/lib.sh` | Test helpers: assertions, curl mock, tmp credentials |
| `skills/cc-dropbox/scripts/test/test_auth.sh` | Unit tests for auth.sh |
| `skills/cc-dropbox/scripts/test/test_upload.sh` | Unit tests for upload.sh |
| `skills/cc-dropbox/scripts/test/test_share.sh` | Unit tests for share.sh |
| `skills/cc-dropbox/scripts/test/integration.sh` | Manual end-to-end (gated by env var) |
| `README.md` | Human install/setup guide |
| `CHANGELOG.md` | Version history |

---

## Task 1: Plugin scaffolding

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `skills/cc-dropbox/SKILL.md` (skeleton)
- Create: `skills/cc-dropbox/scripts/.gitkeep`
- Create: `README.md` (stub)
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "cc-dropbox",
  "version": "0.1.0",
  "description": "Dropbox file operations (upload/download/share) for Claude Code",
  "author": "axect"
}
```

- [ ] **Step 2: Create skeleton `skills/cc-dropbox/SKILL.md`**

```markdown
---
name: cc-dropbox
description: Upload files to Dropbox, download from Dropbox, and create/retrieve shared links. Use when the user mentions Dropbox, asks to upload/download/share a file via Dropbox, or wants a shareable link for a file already in their Dropbox.
---

# cc-dropbox

Dropbox file operations. Full usage rules added in Task 14.
```

- [ ] **Step 3: Create `README.md` stub**

```markdown
# cc-dropbox

A Claude Code plugin that unifies Dropbox upload, download, and shared-link operations.

Full installation and setup guide: see Task 15 output.
```

- [ ] **Step 4: Create empty `CHANGELOG.md`**

```markdown
# Changelog

## [Unreleased]

### Added
- Initial plugin scaffolding
```

- [ ] **Step 5: Create `skills/cc-dropbox/scripts/.gitkeep` (empty file)**

- [ ] **Step 6: Verify layout**

Run: `find .claude-plugin skills -type f | sort`
Expected:
```
.claude-plugin/plugin.json
skills/cc-dropbox/SKILL.md
skills/cc-dropbox/scripts/.gitkeep
```

- [ ] **Step 7: Commit**

```bash
git checkout dev
git checkout -b feature/scaffold
git add .claude-plugin skills README.md CHANGELOG.md
git commit -m "feat: scaffold plugin layout and placeholders"
```

---

## Task 2: Test infrastructure

**Files:**
- Create: `skills/cc-dropbox/scripts/test/lib.sh`
- Create: `skills/cc-dropbox/scripts/test/run_tests.sh`
- Create: `skills/cc-dropbox/scripts/test/test_smoke.sh` (self-check of the runner)

- [ ] **Step 1: Write `scripts/test/lib.sh`**

```bash
# shellcheck shell=bash
# Test helpers shared by all test_*.sh files.

TEST_PASS=0
TEST_FAIL=0
TEST_NAME="${TEST_NAME:-unknown}"

_fail() {
  TEST_FAIL=$((TEST_FAIL + 1))
  echo "  FAIL [$TEST_NAME]: $*" >&2
}

_pass() {
  TEST_PASS=$((TEST_PASS + 1))
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-values differ}"
  if [[ "$expected" == "$actual" ]]; then
    _pass
  else
    _fail "$msg: expected '$expected', got '$actual'"
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-exit code}"
  if [[ "$expected" == "$actual" ]]; then
    _pass
  else
    _fail "$msg: expected $expected, got $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-substring missing}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _pass
  else
    _fail "$msg: '$needle' not in '$haystack'"
  fi
}

# Create an isolated HOME with an empty ~/.config/cc-dropbox directory.
# Sets HOME to the temp dir and returns the path.
make_tmp_home() {
  local tmp
  tmp=$(mktemp -d)
  export HOME="$tmp"
  mkdir -p "$tmp/.config/cc-dropbox"
  echo "$tmp"
}

# Write a credentials.json into the current HOME.
write_creds() {
  local json="$1"
  mkdir -p "$HOME/.config/cc-dropbox"
  printf '%s' "$json" > "$HOME/.config/cc-dropbox/credentials.json"
  chmod 600 "$HOME/.config/cc-dropbox/credentials.json"
}

# Mock curl: responds based on $MOCK_CURL_RESPONSE (body) and
# $MOCK_CURL_HTTP_CODE (default 200). Records the last invocation
# args into $MOCK_CURL_LAST_ARGS for assertions.
# The scripts under test must use:
#   response=$(curl -sS -w '\n%{http_code}' ...)
# so the mock appends http_code on a new line too.
mock_curl() {
  curl() {
    MOCK_CURL_LAST_ARGS="$*"
    local code="${MOCK_CURL_HTTP_CODE:-200}"
    printf '%s\n%s' "${MOCK_CURL_RESPONSE:-}" "$code"
  }
  export -f curl
}

unmock_curl() {
  unset -f curl 2>/dev/null || true
}
```

- [ ] **Step 2: Write `scripts/test/run_tests.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOTAL_PASS=0
TOTAL_FAIL=0

shopt -s nullglob
for test_file in "$TEST_DIR"/test_*.sh; do
  echo "=== $(basename "$test_file") ==="
  # Run in subshell to isolate exports/HOME/etc.
  output=$(bash -c "
    source '$TEST_DIR/lib.sh'
    source '$test_file'
    echo \"__PASS__:\$TEST_PASS\"
    echo \"__FAIL__:\$TEST_FAIL\"
  " 2>&1) || true
  # Extract counters
  pass=$(echo "$output" | awk -F: '/^__PASS__:/{print $2}' | tail -1)
  fail=$(echo "$output" | awk -F: '/^__FAIL__:/{print $2}' | tail -1)
  pass=${pass:-0}
  fail=${fail:-0}
  # Print anything that isn't a counter line
  echo "$output" | grep -v '^__PASS__:\|^__FAIL__:' || true
  echo "  pass=$pass fail=$fail"
  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))
done

echo "---"
echo "TOTAL: pass=$TOTAL_PASS fail=$TOTAL_FAIL"
[[ "$TOTAL_FAIL" -eq 0 ]]
```

- [ ] **Step 3: Write a smoke test `scripts/test/test_smoke.sh`**

```bash
# shellcheck shell=bash
TEST_NAME="smoke"

assert_eq "hello" "hello" "string equality"
assert_exit_code 0 0 "zero exit"
assert_contains "the quick brown fox" "quick" "contains quick"
```

- [ ] **Step 4: Make runner executable and run it**

```bash
chmod +x skills/cc-dropbox/scripts/test/run_tests.sh
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected:
```
=== test_smoke.sh ===
  pass=3 fail=0
---
TOTAL: pass=3 fail=0
```

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/test
git commit -m "test: add bash test runner and assertion helpers"
```

---

## Task 3: auth.sh — missing credentials check (TDD)

**Files:**
- Create: `skills/cc-dropbox/scripts/auth.sh`
- Create: `skills/cc-dropbox/scripts/test/test_auth.sh`

- [ ] **Step 1: Write the failing test**

Append to `skills/cc-dropbox/scripts/test/test_auth.sh`:

```bash
# shellcheck shell=bash
TEST_NAME="auth"

AUTH_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/auth.sh"

# --- case: credentials.json missing ---
make_tmp_home >/dev/null

(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err
code=$?

assert_exit_code 2 "$code" "missing creds should exit 2"
assert_contains "$(cat /tmp/cc_err)" "setup.sh" "error mentions setup.sh"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: `test_auth.sh` fails (auth.sh does not exist yet).

- [ ] **Step 3: Write minimal `auth.sh`**

Create `skills/cc-dropbox/scripts/auth.sh`:

```bash
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
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: `test_auth.sh` pass=2 fail=0.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/auth.sh skills/cc-dropbox/scripts/test/test_auth.sh
git commit -m "feat(auth): error when credentials.json missing"
```

---

## Task 4: auth.sh — cached access token reuse (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/auth.sh`
- Modify: `skills/cc-dropbox/scripts/test/test_auth.sh`

- [ ] **Step 1: Write the failing test**

Append to `skills/cc-dropbox/scripts/test/test_auth.sh`:

```bash
# --- case: cached token still valid ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"cached_token\",\"access_token_expires_at\":$future
}"

# Mock curl — should NOT be called in this case.
MOCK_CURL_RESPONSE='{"error":"should_not_be_called"}'
MOCK_CURL_HTTP_CODE=500
mock_curl

out=$(
  source "$AUTH_SH"
  get_access_token
)
code=$?

assert_exit_code 0 "$code" "cached path returns 0"
assert_eq "cached_token" "$out" "returns cached token"
unmock_curl
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: new assertions fail (`auth.sh` still returns 99 stub).

- [ ] **Step 3: Implement cached token path**

Replace the body of `get_access_token` in `skills/cc-dropbox/scripts/auth.sh`:

```bash
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
```

- [ ] **Step 4: Run tests**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: test_auth now has pass=4 fail=0.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/auth.sh skills/cc-dropbox/scripts/test/test_auth.sh
git commit -m "feat(auth): reuse cached access token when not expired"
```

---

## Task 5: auth.sh — refresh token flow (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/auth.sh`
- Modify: `skills/cc-dropbox/scripts/test/test_auth.sh`

- [ ] **Step 1: Write the failing test**

Append to `test_auth.sh`:

```bash
# --- case: expired token triggers refresh ---
make_tmp_home >/dev/null
past=$(( $(date +%s) - 100 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='{"access_token":"fresh_token","expires_in":14400,"token_type":"bearer"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

out=$(
  source "$AUTH_SH"
  get_access_token
)
code=$?

assert_exit_code 0 "$code" "refresh returns 0"
assert_eq "fresh_token" "$out" "returns new access token"

# Verify credentials.json was updated.
new_token=$(jq -r '.access_token' "$HOME/.config/cc-dropbox/credentials.json")
assert_eq "fresh_token" "$new_token" "credentials.json updated"

new_exp=$(jq -r '.access_token_expires_at' "$HOME/.config/cc-dropbox/credentials.json")
now=$(date +%s)
if (( new_exp > now + 14000 && new_exp < now + 14500 )); then
  _pass
else
  _fail "expires_at not in expected window: $new_exp (now=$now)"
fi
unmock_curl
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: new assertions fail.

- [ ] **Step 3: Implement refresh path in auth.sh**

Replace the `# Refresh path — implemented in Task 5.` block with:

```bash
  # Refresh the access token.
  local app_key app_secret refresh_token
  app_key=$(jq -r '.app_key' "$CC_DROPBOX_CREDS")
  app_secret=$(jq -r '.app_secret' "$CC_DROPBOX_CREDS")
  refresh_token=$(jq -r '.refresh_token' "$CC_DROPBOX_CREDS")

  local response body http_code
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

  local new_access new_expires_in new_expires_at
  new_access=$(printf '%s' "$body" | jq -r '.access_token')
  new_expires_in=$(printf '%s' "$body" | jq -r '.expires_in')
  new_expires_at=$(( now + new_expires_in ))

  local tmp
  tmp=$(mktemp)
  jq --arg tok "$new_access" --argjson exp "$new_expires_at" \
    '.access_token = $tok | .access_token_expires_at = $exp' \
    "$CC_DROPBOX_CREDS" > "$tmp"
  mv "$tmp" "$CC_DROPBOX_CREDS"
  chmod 600 "$CC_DROPBOX_CREDS"

  printf '%s' "$new_access"
  return 0
}
```

- [ ] **Step 4: Run tests**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: test_auth pass includes refresh case.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/auth.sh skills/cc-dropbox/scripts/test/test_auth.sh
git commit -m "feat(auth): refresh expired access tokens via OAuth2"
```

---

## Task 6: auth.sh — invalid_grant error (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/test/test_auth.sh`

- [ ] **Step 1: Write the failing test**

Append to `test_auth.sh`:

```bash
# --- case: refresh returns invalid_grant ---
make_tmp_home >/dev/null
past=$(( $(date +%s) - 100 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"old\",\"access_token_expires_at\":$past
}"

MOCK_CURL_RESPONSE='{"error":"invalid_grant","error_description":"refresh token is invalid"}'
MOCK_CURL_HTTP_CODE=400
mock_curl

(
  source "$AUTH_SH"
  get_access_token
) >/tmp/cc_out 2>/tmp/cc_err
code=$?

assert_exit_code 3 "$code" "invalid_grant exits 3"
assert_contains "$(cat /tmp/cc_err)" "Re-run setup.sh" "error guides user"
unmock_curl
```

- [ ] **Step 2: Run tests**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: pass (Task 5's implementation already handles this).

- [ ] **Step 3: Commit**

```bash
git add skills/cc-dropbox/scripts/test/test_auth.sh
git commit -m "test(auth): cover invalid_grant error path"
```

---

## Task 7: auth.sh — api_call helper (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/auth.sh`
- Modify: `skills/cc-dropbox/scripts/test/test_auth.sh`

`api_call` is the shared helper for JSON-body endpoints on `api.dropboxapi.com`. Operation scripts will use it; file-upload/download use `curl` directly because they hit `content.dropboxapi.com` with non-JSON bodies.

- [ ] **Step 1: Write the failing test**

Append to `test_auth.sh`:

```bash
# --- case: api_call success ---
MOCK_CURL_RESPONSE='{"ok":true,"value":42}'
MOCK_CURL_HTTP_CODE=200
mock_curl

out=$(
  source "$AUTH_SH"
  api_call "https://api.dropboxapi.com/2/some/endpoint" \
           '{"k":"v"}' "TESTTOKEN"
)
code=$?
assert_exit_code 0 "$code" "api_call 200 returns 0"
assert_contains "$out" '"value":42' "returns body"

# --- case: api_call non-2xx ---
MOCK_CURL_RESPONSE='{"error_summary":"path/not_found/"}'
MOCK_CURL_HTTP_CODE=409
mock_curl

(
  source "$AUTH_SH"
  api_call "https://api.dropboxapi.com/2/x" '{}' "T"
) >/tmp/cc_out 2>/tmp/cc_err
code=$?
assert_exit_code 5 "$code" "non-2xx exits 5 by default"
assert_contains "$(cat /tmp/cc_err)" "path/not_found" "dumps raw body"
unmock_curl
```

- [ ] **Step 2: Run tests — expect failure**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Add `api_call` to `auth.sh`**

Append to `skills/cc-dropbox/scripts/auth.sh`:

```bash
# api_call <url> <json_body> <bearer_token>
# Echoes response body on success (HTTP 2xx), exits non-zero on error.
# On non-2xx: dumps body to stderr, returns 5 (caller may intercept before this
# via its own response parsing if it needs custom 409 handling).
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
```

- [ ] **Step 4: Run tests — expect pass**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/auth.sh skills/cc-dropbox/scripts/test/test_auth.sh
git commit -m "feat(auth): add api_call helper for JSON endpoints"
```

---

## Task 8: setup.sh — OAuth2 bootstrap

**Files:**
- Create: `skills/cc-dropbox/scripts/setup.sh`
- Create: `skills/cc-dropbox/scripts/test/test_setup.sh`

`setup.sh` is mostly interactive. We factor the pure logic (token exchange → credentials.json write) into a function `exchange_code` that tests can call directly.

- [ ] **Step 1: Write the failing test**

Create `skills/cc-dropbox/scripts/test/test_setup.sh`:

```bash
# shellcheck shell=bash
TEST_NAME="setup"

SETUP_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup.sh"

make_tmp_home >/dev/null

MOCK_CURL_RESPONSE='{"access_token":"AT","refresh_token":"RT","expires_in":14400}'
MOCK_CURL_HTTP_CODE=200
mock_curl

(
  source "$SETUP_SH"
  exchange_code "app_k" "app_s" "the_code"
)
code=$?
assert_exit_code 0 "$code" "exchange_code returns 0"

creds="$HOME/.config/cc-dropbox/credentials.json"
if [[ -f "$creds" ]]; then _pass; else _fail "credentials.json not created"; fi
assert_eq "app_k" "$(jq -r .app_key "$creds")" "app_key stored"
assert_eq "app_s" "$(jq -r .app_secret "$creds")" "app_secret stored"
assert_eq "RT" "$(jq -r .refresh_token "$creds")" "refresh_token stored"
assert_eq "AT" "$(jq -r .access_token "$creds")" "access_token stored"
perm=$(stat -c %a "$creds")
assert_eq "600" "$perm" "credentials.json is chmod 600"
unmock_curl
```

- [ ] **Step 2: Run tests — expect failure (setup.sh missing)**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement `setup.sh`**

Create `skills/cc-dropbox/scripts/setup.sh`:

```bash
#!/usr/bin/env bash
# cc-dropbox setup: interactive OAuth2 bootstrap.
# Sourceable for tests: defines exchange_code(). If executed directly, runs
# the interactive flow at the bottom.

set -uo pipefail

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
# writes credentials.json.
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

  local access refresh expires_in now expires_at
  access=$(printf '%s' "$body" | jq -r '.access_token')
  refresh=$(printf '%s' "$body" | jq -r '.refresh_token')
  expires_in=$(printf '%s' "$body" | jq -r '.expires_in')
  now=$(date +%s)
  expires_at=$(( now + expires_in ))

  mkdir -p "$(dirname "$CC_DROPBOX_CREDS")"
  local tmp
  tmp=$(mktemp)
  jq -n \
    --arg ak "$app_key" \
    --arg as "$app_secret" \
    --arg rt "$refresh" \
    --arg at "$access" \
    --argjson exp "$expires_at" \
    '{app_key:$ak, app_secret:$as, refresh_token:$rt, access_token:$at, access_token_expires_at:$exp}' \
    > "$tmp"
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
```

- [ ] **Step 4: Mark executable and run tests**

```bash
chmod +x skills/cc-dropbox/scripts/setup.sh
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: test_setup assertions pass.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/setup.sh skills/cc-dropbox/scripts/test/test_setup.sh
git commit -m "feat(setup): OAuth2 bootstrap with exchange_code()"
```

---

## Task 9: upload.sh — small file path (TDD)

**Files:**
- Create: `skills/cc-dropbox/scripts/upload.sh`
- Create: `skills/cc-dropbox/scripts/test/test_upload.sh`

Initial version covers files ≤ 150 MB via `/2/files/upload` (single-shot).

- [ ] **Step 1: Write the failing test**

Create `skills/cc-dropbox/scripts/test/test_upload.sh`:

```bash
# shellcheck shell=bash
TEST_NAME="upload"

UPLOAD_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/upload.sh"

# --- case: small file single-shot upload ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

tmp_file=$(mktemp)
echo "hello dropbox" > "$tmp_file"

MOCK_CURL_RESPONSE='{"path_display":"/t/hello.txt","size":14,"content_hash":"abc123"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

out=$(bash "$UPLOAD_SH" "$tmp_file" "/t/hello.txt")
code=$?
assert_exit_code 0 "$code" "upload returns 0"
assert_contains "$out" '"path":"/t/hello.txt"' "summary includes path"
assert_contains "$out" '"size":14' "summary includes size"
assert_contains "$out" '"content_hash":"abc123"' "summary includes hash"
unmock_curl
rm -f "$tmp_file"

# --- case: missing local file ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
(bash "$UPLOAD_SH" "/no/such/file" "/t/x.txt") >/tmp/cc_out 2>/tmp/cc_err
code=$?
assert_exit_code 1 "$code" "missing file exits 1"
assert_contains "$(cat /tmp/cc_err)" "Cannot read" "error mentions cannot read"
```

- [ ] **Step 2: Run tests — expect failure**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement `upload.sh`**

Create `skills/cc-dropbox/scripts/upload.sh`:

```bash
#!/usr/bin/env bash
# cc-dropbox upload: upload a local file to Dropbox.
# Usage: upload.sh <local_path> <dropbox_path>
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

CHUNK_THRESHOLD=$((150 * 1024 * 1024))  # 150 MB
CHUNK_SIZE=$((8 * 1024 * 1024))         # 8 MB

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
```

- [ ] **Step 4: Mark executable and run tests**

```bash
chmod +x skills/cc-dropbox/scripts/upload.sh
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: test_upload small-file + missing-file cases pass.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/upload.sh skills/cc-dropbox/scripts/test/test_upload.sh
git commit -m "feat(upload): single-shot upload for files <=150MB"
```

---

## Task 10: upload.sh — chunked upload session (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/upload.sh`
- Modify: `skills/cc-dropbox/scripts/test/test_upload.sh`

The chunked path calls three endpoints (start, append_v2, finish). We test size-branch selection with a patched threshold so we don't actually create a 150 MB file.

- [ ] **Step 1: Write the failing test**

Append to `test_upload.sh`:

```bash
# --- case: chunked path is taken when size exceeds threshold ---
# We do NOT want to create a 150MB file; instead we call upload.sh with
# CC_DROPBOX_CHUNK_THRESHOLD=10 to force the chunked path for a 20-byte file.
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

tmp_file=$(mktemp)
printf '%s' "0123456789ABCDEFGHIJ" > "$tmp_file"   # 20 bytes

# The mock returns a generic OK body for each call. start returns session_id.
# We're only verifying: chunked branch was taken (no error exit 99), final
# summary is printed. Fine-grained request verification is handled in
# integration tests.
mock_curl_chunked() {
  local call=0
  curl() {
    call=$((call + 1))
    case "$call" in
      1) printf '%s\n%s' '{"session_id":"SID"}' '200' ;;
      2) printf '%s\n%s' '{}' '200' ;;
      3) printf '%s\n%s' '{"path_display":"/t/big.bin","size":20,"content_hash":"ZZZ"}' '200' ;;
      *) printf '%s\n%s' '{}' '200' ;;
    esac
  }
  export -f curl
}
mock_curl_chunked

out=$(
  CC_DROPBOX_CHUNK_THRESHOLD=10 CC_DROPBOX_CHUNK_SIZE=8 \
    bash "$UPLOAD_SH" "$tmp_file" "/t/big.bin"
)
code=$?
assert_exit_code 0 "$code" "chunked returns 0"
assert_contains "$out" '"path":"/t/big.bin"' "chunked summary path"
assert_contains "$out" '"size":20' "chunked summary size"
unmock_curl
rm -f "$tmp_file"
```

- [ ] **Step 2: Run tests — expect failure**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement chunked_upload**

In `skills/cc-dropbox/scripts/upload.sh`, replace these two lines:

```bash
CHUNK_THRESHOLD=$((150 * 1024 * 1024))  # 150 MB
CHUNK_SIZE=$((8 * 1024 * 1024))         # 8 MB
```

with:

```bash
CHUNK_THRESHOLD="${CC_DROPBOX_CHUNK_THRESHOLD:-$((150 * 1024 * 1024))}"
CHUNK_SIZE="${CC_DROPBOX_CHUNK_SIZE:-$((8 * 1024 * 1024))}"
```

Then replace the `chunked_upload` function body with:

```bash
chunked_upload() {
  local total_chunks=$(( (SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
  local offset=0 session_id="" idx=0
  local response http_code body arg

  # --- start: first chunk ---
  idx=1
  echo "[$idx/$total_chunks] uploading chunk..." >&2
  arg=$(jq -nc '{close:false}')
  response=$(dd if="$LOCAL" bs="$CHUNK_SIZE" skip=0 count=1 status=none \
    | curl -sS -w $'\n%{http_code}' \
      -X POST "https://content.dropboxapi.com/2/files/upload_session/start" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Dropbox-API-Arg: $arg" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @-)
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [[ "$http_code" != "200" ]]; then
    echo "cc-dropbox: upload_session/start failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  session_id=$(printf '%s' "$body" | jq -r '.session_id')
  offset=$(( CHUNK_SIZE < SIZE ? CHUNK_SIZE : SIZE ))

  # --- append middle chunks ---
  while (( offset < SIZE )); do
    idx=$((idx + 1))
    local remaining=$(( SIZE - offset ))
    if (( remaining <= CHUNK_SIZE )); then
      break   # last chunk goes via finish
    fi
    echo "[$idx/$total_chunks] uploading chunk..." >&2
    arg=$(jq -nc \
      --arg sid "$session_id" \
      --argjson off "$offset" \
      '{cursor:{session_id:$sid, offset:$off}, close:false}')
    local skip=$(( offset / CHUNK_SIZE ))
    response=$(dd if="$LOCAL" bs="$CHUNK_SIZE" skip="$skip" count=1 status=none \
      | curl -sS -w $'\n%{http_code}' \
        -X POST "https://content.dropboxapi.com/2/files/upload_session/append_v2" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Dropbox-API-Arg: $arg" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @-)
    http_code=$(printf '%s' "$response" | tail -n1)
    body=$(printf '%s' "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
      echo "cc-dropbox: upload_session/append_v2 failed (HTTP $http_code): $body" >&2
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
  response=$(dd if="$LOCAL" bs="$CHUNK_SIZE" skip="$skip" count=1 status=none \
    | curl -sS -w $'\n%{http_code}' \
      -X POST "https://content.dropboxapi.com/2/files/upload_session/finish" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Dropbox-API-Arg: $arg" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @-)
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [[ "$http_code" != "200" ]]; then
    echo "cc-dropbox: upload_session/finish failed (HTTP $http_code): $body" >&2
    exit 5
  fi
  printf '%s' "$body" | jq -c '{path:.path_display, size, content_hash}'
}
```

- [ ] **Step 4: Run tests**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: chunked-path test passes.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/upload.sh skills/cc-dropbox/scripts/test/test_upload.sh
git commit -m "feat(upload): chunked upload session for files >150MB"
```

---

## Task 11: download.sh (TDD)

**Files:**
- Create: `skills/cc-dropbox/scripts/download.sh`
- Create: `skills/cc-dropbox/scripts/test/test_download.sh`

- [ ] **Step 1: Write the failing test**

Create `skills/cc-dropbox/scripts/test/test_download.sh`:

```bash
# shellcheck shell=bash
TEST_NAME="download"

DL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/download.sh"

# --- case: download writes file to specified local path ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Custom mock: download writes bytes to --output <path>, prints HTTP 200.
mock_curl_download() {
  curl() {
    local out_path=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--output" ]]; then
        out_path="$2"; shift 2
      else
        shift
      fi
    done
    if [[ -n "$out_path" ]]; then
      printf 'dropbox body content' > "$out_path"
    fi
    printf '%s\n%s' '' '200'
  }
  export -f curl
}
mock_curl_download

dest=$(mktemp -u)
out=$(bash "$DL_SH" "/remote/file.txt" "$dest")
code=$?
assert_exit_code 0 "$code" "download returns 0"
if [[ -f "$dest" ]]; then _pass; else _fail "dest file not created"; fi
assert_eq "dropbox body content" "$(cat "$dest")" "content written"
assert_eq "$dest" "$out" "prints saved path"
rm -f "$dest"
unmock_curl

# --- case: refuses to overwrite existing local file ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
existing=$(mktemp)
echo "do not clobber" > "$existing"
(bash "$DL_SH" "/remote/file.txt" "$existing") >/tmp/cc_out 2>/tmp/cc_err
code=$?
assert_exit_code 1 "$code" "existing file exits 1"
assert_contains "$(cat /tmp/cc_err)" "File exists" "error mentions exists"
assert_eq "do not clobber" "$(cat "$existing")" "original untouched"
rm -f "$existing"
```

- [ ] **Step 2: Run tests — expect failure**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement `download.sh`**

Create `skills/cc-dropbox/scripts/download.sh`:

```bash
#!/usr/bin/env bash
# cc-dropbox download: fetch a file from Dropbox.
# Usage: download.sh <dropbox_path> [<local_path>]
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./auth.sh
source "$SCRIPT_DIR/auth.sh"

usage() {
  echo "Usage: download.sh <dropbox_path> [<local_path>]" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
REMOTE="$1"
LOCAL="${2:-}"

if [[ "${REMOTE:0:1}" != "/" ]]; then
  echo "cc-dropbox: dropbox path must start with '/': $REMOTE" >&2
  exit 1
fi

if [[ -z "$LOCAL" ]]; then
  LOCAL="$(basename "$REMOTE")"
fi

if [[ -e "$LOCAL" ]]; then
  echo "cc-dropbox: File exists: $LOCAL. Remove it or specify a different destination." >&2
  exit 1
fi

TOKEN=$(get_access_token) || exit $?

arg=$(jq -nc --arg path "$REMOTE" '{path:$path}')
response=$(curl -sS -w $'\n%{http_code}' \
  -X POST "https://content.dropboxapi.com/2/files/download" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Dropbox-API-Arg: $arg" \
  --output "$LOCAL")
http_code=$(printf '%s' "$response" | tail -n1)

if [[ "$http_code" == "200" ]]; then
  printf '%s\n' "$LOCAL"
  exit 0
fi

# On non-200, Dropbox wrote an error JSON to the output file. Read and clean up.
if [[ -f "$LOCAL" ]]; then
  err_body=$(cat "$LOCAL")
  rm -f "$LOCAL"
else
  err_body=""
fi

if [[ "$http_code" == "409" ]] && printf '%s' "$err_body" | jq -e '.error_summary | startswith("path/not_found")' >/dev/null 2>&1; then
  echo "cc-dropbox: Not found: $REMOTE" >&2
  exit 4
fi

echo "cc-dropbox: download failed (HTTP $http_code): $err_body" >&2
exit 5
```

- [ ] **Step 4: Run tests**

```bash
chmod +x skills/cc-dropbox/scripts/download.sh
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: test_download passes.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/download.sh skills/cc-dropbox/scripts/test/test_download.sh
git commit -m "feat(download): download with no-overwrite guard and 404 detection"
```

---

## Task 12: share.sh — new link creation (TDD)

**Files:**
- Create: `skills/cc-dropbox/scripts/share.sh`
- Create: `skills/cc-dropbox/scripts/test/test_share.sh`

- [ ] **Step 1: Write the failing test**

Create `skills/cc-dropbox/scripts/test/test_share.sh`:

```bash
# shellcheck shell=bash
TEST_NAME="share"

SHARE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/share.sh"

# --- case: create_shared_link_with_settings returns 200 ---
make_tmp_home >/dev/null
future=$(( $(date +%s) + 3600 ))
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

MOCK_CURL_RESPONSE='{"url":"https://www.dropbox.com/scl/fi/abc/file.txt?dl=0","id":"id:xxx"}'
MOCK_CURL_HTTP_CODE=200
mock_curl

out=$(bash "$SHARE_SH" "/remote/file.txt")
code=$?
assert_exit_code 0 "$code" "share returns 0"
assert_eq "https://www.dropbox.com/scl/fi/abc/file.txt?dl=0" "$out" "prints URL"
unmock_curl

# --- case: path_not_found ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"
MOCK_CURL_RESPONSE='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}'
MOCK_CURL_HTTP_CODE=409
mock_curl
(bash "$SHARE_SH" "/missing.txt") >/tmp/cc_out 2>/tmp/cc_err
code=$?
assert_exit_code 4 "$code" "not_found exits 4"
assert_contains "$(cat /tmp/cc_err)" "Not found" "error mentions not found"
unmock_curl
```

- [ ] **Step 2: Run tests — expect failure**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement `share.sh` (first pass)**

Create `skills/cc-dropbox/scripts/share.sh`:

```bash
#!/usr/bin/env bash
# cc-dropbox share: create or retrieve a shared link for a Dropbox path.
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
  echo "cc-dropbox: dropbox path must start with '/': $REMOTE" >&2
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
    echo "cc-dropbox: Not found: $REMOTE" >&2
    exit 4
  fi
  if [[ "$summary" == shared_link_already_exists* ]]; then
    # Retrieval logic implemented in Task 13.
    echo "cc-dropbox: link already exists; retrieval implemented in Task 13." >&2
    exit 98
  fi
fi

echo "cc-dropbox: share failed (HTTP $http_code): $body" >&2
exit 5
```

- [ ] **Step 4: Run tests**

```bash
chmod +x skills/cc-dropbox/scripts/share.sh
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: both test_share cases pass.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/share.sh skills/cc-dropbox/scripts/test/test_share.sh
git commit -m "feat(share): create shared link with public viewer access"
```

---

## Task 13: share.sh — reuse existing link (TDD)

**Files:**
- Modify: `skills/cc-dropbox/scripts/share.sh`
- Modify: `skills/cc-dropbox/scripts/test/test_share.sh`

When the first call returns `shared_link_already_exists`, fall back to `list_shared_links` and return the existing URL.

- [ ] **Step 1: Write the failing test**

Append to `test_share.sh`:

```bash
# --- case: shared_link_already_exists → list_shared_links fallback ---
make_tmp_home >/dev/null
write_creds "{
  \"app_key\":\"k\",\"app_secret\":\"s\",\"refresh_token\":\"r\",
  \"access_token\":\"AT\",\"access_token_expires_at\":$future
}"

# Two-call mock: first create returns 409, then list returns 200.
mock_curl_share_reuse() {
  local call=0
  curl() {
    call=$((call + 1))
    case "$call" in
      1) printf '%s\n%s' '{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}' '409' ;;
      2) printf '%s\n%s' '{"links":[{"url":"https://www.dropbox.com/s/existing/file.txt?dl=0"}],"has_more":false}' '200' ;;
      *) printf '%s\n%s' '{}' '500' ;;
    esac
  }
  export -f curl
}
mock_curl_share_reuse

out=$(bash "$SHARE_SH" "/remote/file.txt")
code=$?
assert_exit_code 0 "$code" "reuse returns 0"
assert_eq "https://www.dropbox.com/s/existing/file.txt?dl=0" "$out" "returns existing URL"
unmock_curl
```

- [ ] **Step 2: Run tests — expect failure (currently exits 98)**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

- [ ] **Step 3: Implement fallback in `share.sh`**

Replace this block in `share.sh`:

```bash
  if [[ "$summary" == shared_link_already_exists* ]]; then
    # Retrieval logic implemented in Task 13.
    echo "cc-dropbox: link already exists; retrieval implemented in Task 13." >&2
    exit 98
  fi
```

with:

```bash
  if [[ "$summary" == shared_link_already_exists* ]]; then
    list_body=$(jq -nc --arg p "$REMOTE" '{path:$p, direct_only:true}')
    response=$(curl -sS -w $'\n%{http_code}' \
      -X POST "https://api.dropboxapi.com/2/sharing/list_shared_links" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$list_body")
    http_code=$(printf '%s' "$response" | tail -n1)
    body=$(printf '%s' "$response" | sed '$d')
    if [[ "$http_code" != "200" ]]; then
      echo "cc-dropbox: list_shared_links failed (HTTP $http_code): $body" >&2
      exit 5
    fi
    url=$(printf '%s' "$body" | jq -r '.links[0].url // ""')
    if [[ -z "$url" ]]; then
      echo "cc-dropbox: no existing shared link found for $REMOTE" >&2
      exit 5
    fi
    printf '%s\n' "$url"
    exit 0
  fi
```

- [ ] **Step 4: Run tests**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: all test_share cases pass.

- [ ] **Step 5: Commit**

```bash
git add skills/cc-dropbox/scripts/share.sh skills/cc-dropbox/scripts/test/test_share.sh
git commit -m "feat(share): reuse existing shared link via list_shared_links"
```

---

## Task 14: Flesh out SKILL.md

**Files:**
- Modify: `skills/cc-dropbox/SKILL.md`

- [ ] **Step 1: Replace SKILL.md with full content**

Overwrite `skills/cc-dropbox/SKILL.md` with:

```markdown
---
name: cc-dropbox
description: Upload files to Dropbox, download from Dropbox, and create/retrieve shared links. Use when the user mentions Dropbox, asks to upload/download/share a file via Dropbox, or wants a shareable link for a file already in their Dropbox.
---

# cc-dropbox

Dropbox file operations via Dropbox HTTP API v2. Unifies upload, download, and shared-link operations.

## Trigger conditions

Invoke this skill when the user says any of:
- "upload X to Dropbox" → use `scripts/upload.sh`
- "download X from Dropbox" / "get X from Dropbox" → `scripts/download.sh`
- "share link", "shared link", "Dropbox link", "make a link for X" → `scripts/share.sh`
- "set up Dropbox", "configure Dropbox", or when `~/.config/cc-dropbox/credentials.json` does not exist → `scripts/setup.sh`

## Prerequisites (check before any operation)

Before running upload/download/share, verify the credentials file exists:

    test -f ~/.config/cc-dropbox/credentials.json

If it does not exist, tell the user:
> Dropbox is not set up yet. I can run the setup flow — it will ask for your app key, app secret, and an authorization code from a browser URL. Proceed?

Only run `setup.sh` after the user confirms.

## Path rules

- Dropbox paths MUST start with `/` (e.g. `/Papers/draft.pdf`). Reject relative paths.
- If the user gives a bare filename (e.g. "report.pdf"), ask which Dropbox folder before acting.

## Script usage

### setup.sh
Interactive one-time bootstrap. Takes stdin input for app key, app secret, and authorization code.

    bash skills/cc-dropbox/scripts/setup.sh

### upload.sh
Upload local → Dropbox. Auto-chooses single-shot vs chunked session based on file size.

    bash skills/cc-dropbox/scripts/upload.sh <local_path> <dropbox_path>

Prints a one-line JSON summary on success: `{"path":"...","size":N,"content_hash":"..."}`

### download.sh
Download Dropbox → local. Refuses to overwrite existing local files.

    bash skills/cc-dropbox/scripts/download.sh <dropbox_path> [<local_path>]

If `<local_path>` is omitted, uses `basename <dropbox_path>` in the current directory.
Prints the saved path on stdout.

### share.sh
Create (or retrieve existing) shared link.

    bash skills/cc-dropbox/scripts/share.sh <dropbox_path>

Prints the URL on stdout.

## Error handling

If any script exits non-zero, show its stderr to the user verbatim. Do not retry auth errors automatically (exit codes 2 and 3) — surface them so the user can re-run setup.

Exit code reference:
- 0 — success
- 1 — bad argument or local filesystem error
- 2 — credentials.json missing (→ user should run setup.sh)
- 3 — refresh token rejected (→ user should re-run setup.sh)
- 4 — Dropbox path not found
- 5 — other API error
- 64 — usage error
- 127 — missing dependency (curl/jq)
```

- [ ] **Step 2: Commit**

```bash
git add skills/cc-dropbox/SKILL.md
git commit -m "docs(skill): full trigger rules and script usage"
```

---

## Task 15: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Overwrite README.md**

```markdown
# cc-dropbox

A Claude Code plugin that unifies Dropbox file operations — **upload**, **download**, and **shared link** — into one skill. Claude invokes bash scripts in response to natural-language requests like "upload this PDF to Dropbox" or "make a share link for `/Papers/draft.pdf`".

## Features

- Upload files of any size (auto chunked upload session for > 150 MB)
- Download files with overwrite protection
- Create and retrieve shared links (reuses existing links automatically)
- OAuth2 refresh-token flow with on-demand access-token caching
- Zero runtime dependencies beyond `curl` and `jq`

## Requirements

- `bash`, `curl`, `jq`, standard coreutils (`stat`, `dd`, `mktemp`)
- A Dropbox account
- A registered Dropbox app (see Setup)

## Installation

Install as a Claude Code plugin:

    /plugin install <this repo>

Claude will pick up `skills/cc-dropbox/SKILL.md` automatically.

## Setup (one time)

1. Go to https://www.dropbox.com/developers/apps and click **Create app**.
2. Choose:
   - API: **Scoped access**
   - Access type: **Full Dropbox**
   - Name: anything (e.g. `claude-code-skill`)
3. On the app page, open the **Permissions** tab and enable:
   - `files.content.write`
   - `files.content.read`
   - `sharing.write`
   - `sharing.read`

   Click **Submit**.
4. Note the **App key** and **App secret** from the Settings tab.
5. Run the setup script:

        bash skills/cc-dropbox/scripts/setup.sh

   Or just tell Claude: *"set up Dropbox"*.

   The script will:
   - Prompt for your app key and app secret (secret is hidden).
   - Print a URL to open in a browser for OAuth authorization.
   - Prompt you to paste the authorization code shown by Dropbox.
   - Exchange the code for an access token + refresh token and save them to `~/.config/cc-dropbox/credentials.json` (`chmod 600`).

## Usage (via Claude)

Just talk to Claude:

- *"Upload `./report.pdf` to `/Papers/report.pdf` in Dropbox."*
- *"Download `/Papers/draft.pdf` from Dropbox."*
- *"Make a share link for `/Papers/draft.pdf`."*

## Usage (direct)

You can also call the scripts directly:

    bash skills/cc-dropbox/scripts/upload.sh ./report.pdf /Papers/report.pdf
    bash skills/cc-dropbox/scripts/download.sh /Papers/draft.pdf
    bash skills/cc-dropbox/scripts/share.sh /Papers/draft.pdf

## Security

- Credentials are stored at `~/.config/cc-dropbox/credentials.json` with `chmod 600`.
- Access tokens are refreshed on demand; only the refresh token persists.
- `.gitignore` excludes all `credentials*` files from ever being committed.

## Testing

Unit tests (mocked curl) run offline:

    bash skills/cc-dropbox/scripts/test/run_tests.sh

Integration test (hits real Dropbox, requires credentials):

    DROPBOX_INTEGRATION_TEST=1 bash skills/cc-dropbox/scripts/test/integration.sh

## License

See `LICENSE` (if present).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: comprehensive README with install, setup, and usage"
```

---

## Task 16: Integration test script

**Files:**
- Create: `skills/cc-dropbox/scripts/test/integration.sh`

This runs against a real Dropbox account and is gated by `DROPBOX_INTEGRATION_TEST=1`. It is **never** run by `run_tests.sh`.

- [ ] **Step 1: Create integration.sh**

```bash
#!/usr/bin/env bash
# Manual end-to-end test against a real Dropbox account.
# Run with: DROPBOX_INTEGRATION_TEST=1 bash integration.sh
# Requires an already-configured ~/.config/cc-dropbox/credentials.json.
set -euo pipefail

if [[ "${DROPBOX_INTEGRATION_TEST:-}" != "1" ]]; then
  echo "Refusing to run without DROPBOX_INTEGRATION_TEST=1" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REMOTE_DIR="/cc-dropbox-test-$(date +%s)"
SMALL="$REMOTE_DIR/small.bin"
BIG="$REMOTE_DIR/big.bin"

trap 'cleanup' EXIT

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
```

- [ ] **Step 2: Mark executable and verify it refuses without the env var**

```bash
chmod +x skills/cc-dropbox/scripts/test/integration.sh
bash skills/cc-dropbox/scripts/test/integration.sh; echo "exit=$?"
```

Expected: `Refusing to run without DROPBOX_INTEGRATION_TEST=1`, `exit=1`.

- [ ] **Step 3: Run unit tests to confirm nothing regressed**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: all pass, no fail.

- [ ] **Step 4: Commit**

```bash
git add skills/cc-dropbox/scripts/test/integration.sh
git commit -m "test: gated end-to-end integration script"
```

---

## Task 17: Finalize and merge to dev

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update CHANGELOG**

Overwrite `CHANGELOG.md`:

```markdown
# Changelog

## [0.1.0] - 2026-04-10

### Added
- Claude Code plugin scaffolding (`.claude-plugin/plugin.json`, `SKILL.md`)
- `scripts/auth.sh`: OAuth2 refresh-token flow with access-token caching and `api_call` helper
- `scripts/setup.sh`: interactive one-time OAuth2 bootstrap (`exchange_code`)
- `scripts/upload.sh`: single-shot upload (≤150MB) and chunked upload session (>150MB)
- `scripts/download.sh`: download with overwrite protection and 404 detection
- `scripts/share.sh`: create shared link with public viewer access, reuse existing link on conflict
- `scripts/test/`: bash unit test runner with mocked `curl`
- `scripts/test/integration.sh`: gated end-to-end integration script
- `README.md` with installation, setup, usage, and security notes
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "chore: changelog for 0.1.0"
```

- [ ] **Step 3: Run full test suite one more time**

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: all tests pass, no fail.

- [ ] **Step 4: Verify final file layout**

```bash
find . -type f -not -path './.git/*' | sort
```

Expected to include (at minimum):
```
./.claude-plugin/plugin.json
./.gitignore
./CHANGELOG.md
./README.md
./docs/superpowers/plans/2026-04-10-cc-dropbox.md
./docs/superpowers/specs/2026-04-10-cc-dropbox-design.md
./skills/cc-dropbox/SKILL.md
./skills/cc-dropbox/scripts/auth.sh
./skills/cc-dropbox/scripts/download.sh
./skills/cc-dropbox/scripts/setup.sh
./skills/cc-dropbox/scripts/share.sh
./skills/cc-dropbox/scripts/test/integration.sh
./skills/cc-dropbox/scripts/test/lib.sh
./skills/cc-dropbox/scripts/test/run_tests.sh
./skills/cc-dropbox/scripts/test/test_auth.sh
./skills/cc-dropbox/scripts/test/test_download.sh
./skills/cc-dropbox/scripts/test/test_setup.sh
./skills/cc-dropbox/scripts/test/test_share.sh
./skills/cc-dropbox/scripts/test/test_smoke.sh
./skills/cc-dropbox/scripts/test/test_upload.sh
./skills/cc-dropbox/scripts/upload.sh
```

- [ ] **Step 5: Merge feature branch into dev (no PR, local Gitflow)**

```bash
git checkout dev
git merge --no-ff feature/scaffold -m "merge: cc-dropbox initial implementation"
git branch -d feature/scaffold
git log --oneline --decorate --all
```

Expected: `dev` is ahead of `main` by the full feature history.

**Note:** Merging `dev` → `main` for release is deferred — do that only when you are ready to publish to the plugin Marketplace.

---

## Self-Review Notes

- **Spec coverage:** All sections of the spec are covered by tasks 1–17. Scaffolding (Task 1), credentials flow (Tasks 3–7), setup flow (Task 8), upload with both paths (Tasks 9–10), download with overwrite guard (Task 11), share with reuse (Tasks 12–13), SKILL.md (Task 14), README (Task 15), integration test (Task 16), packaging (Task 17).
- **Placeholder scan:** No TBDs, no unresolved "implement later" except explicit stubs-with-task-pointers in Tasks 9 and 12 that are filled in the very next tasks (Tasks 10 and 13 respectively).
- **Type consistency:** `get_access_token` exit codes (0/2/3/5) consistent across all scripts. `api_call` signature `(url, body, token)` consistent. Exit-code table in SKILL.md matches the implementations. `CC_DROPBOX_CHUNK_THRESHOLD`/`CC_DROPBOX_CHUNK_SIZE` env vars match between Task 10 implementation and test.
- **File structure:** Every file listed in Section 3 of the spec is created by at least one task.
