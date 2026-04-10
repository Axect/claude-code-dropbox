# cc-dropbox — Design Spec

**Date:** 2026-04-10
**Status:** Approved (brainstorming complete)
**Form factor:** Claude Code plugin (distributable via Marketplace, Gitflow-managed)

## 1. Goal

A single Claude Code skill that unifies three Dropbox operations:

1. **Upload** a local file to Dropbox (any size, auto chunked for large files)
2. **Download** a file from Dropbox to the local filesystem
3. **Create or retrieve a shared link** for a file already in Dropbox

Triggered by natural language (e.g. "upload this PDF to Dropbox", "make a share link for `/Papers/draft.pdf`"). Claude reads `SKILL.md` and invokes the appropriate bash script.

## 2. Scope decisions (approved)

| Decision | Value |
|---|---|
| Dropbox access type | **Full Dropbox** (not App folder) — needed for share links of arbitrary pre-existing files |
| Credentials storage | `~/.config/cc-dropbox/credentials.json` (permission `600`) |
| Setup flow | Fully automated via `setup.sh` (OAuth2 authorization code + `token_access_type=offline`) |
| Upload overwrite | `mode=overwrite` (same path replaces existing) |
| Large file handling | Auto chunked upload session for files > 150 MB (8 MB chunks) |
| Download destination | CWD by default; refuse to overwrite existing local file |
| Share link options | Public, no expiry (simplest defaults) |
| Existing share link | Reuse via `/sharing/list_shared_links` on `shared_link_already_exists` |

## 3. Directory layout

```
cc-dropbox/                          # project / plugin root
├── .claude-plugin/
│   └── plugin.json                  # plugin metadata
├── skills/
│   └── cc-dropbox/
│       ├── SKILL.md                 # Claude-facing entry point
│       └── scripts/
│           ├── setup.sh             # OAuth refresh token bootstrap
│           ├── auth.sh              # sourceable: get_access_token()
│           ├── upload.sh            # upload (auto chunked)
│           ├── download.sh          # download
│           ├── share.sh             # create/retrieve shared link
│           └── test/
│               ├── run_tests.sh
│               ├── test_auth.sh
│               ├── test_upload.sh
│               ├── test_share.sh
│               └── integration.sh   # manual end-to-end (gated)
├── docs/superpowers/specs/
│   └── 2026-04-10-cc-dropbox-design.md
├── README.md
├── CHANGELOG.md
└── .gitignore
```

**Separation principle:** `SKILL.md` tells Claude *when* to invoke which script; all real logic lives in `scripts/*.sh` so it executes outside Claude's context window.

**Credentials path is outside the project tree** so plugin reinstall does not wipe auth state.

## 4. Credentials file format

`~/.config/cc-dropbox/credentials.json`:

```json
{
  "app_key": "xxxxxxxxxxxxxxx",
  "app_secret": "yyyyyyyyyyyyyyy",
  "refresh_token": "zzzzzzzz...",
  "access_token": "sl.u...",
  "access_token_expires_at": 1712750400
}
```

- First three are written once by `setup.sh` and never rotated by the skill.
- Last two are cached by `auth.sh` and refreshed on demand.
- File is created with `chmod 600`.
- Updates use `mktemp` + `mv` for atomic rewrite (no partial writes under concurrent use).

## 5. Auth flow

### 5.1 `setup.sh` (one-shot, interactive)

1. Check `jq` and `curl` are on `$PATH`; else exit 127.
2. Prompt for `app_key` (stdin).
3. Prompt for `app_secret` (`read -s`, input hidden).
4. Print authorization URL:
   ```
   https://www.dropbox.com/oauth2/authorize
     ?client_id=<app_key>
     &response_type=code
     &token_access_type=offline
   ```
5. Instruct user to open the URL in a browser, approve, and paste the resulting code.
6. Read code from stdin.
7. `POST https://api.dropboxapi.com/oauth2/token` with
   `grant_type=authorization_code`, `code`, `client_id`, `client_secret`.
8. Parse `access_token`, `refresh_token`, `expires_in`.
9. `mkdir -p ~/.config/cc-dropbox`; write `credentials.json` with `chmod 600`.
10. Print `✓ Setup complete`.

**Failure modes:** any HTTP non-2xx → dump raw response to stderr and exit 1.

### 5.2 `auth.sh` — `get_access_token`

Sourceable library providing one function:

```
get_access_token():
  1. Require credentials.json; else stderr "Run setup.sh first", exit 2.
  2. If (now + 60 s buffer) < access_token_expires_at:
       echo "$access_token"; return
  3. Else POST /oauth2/token with grant_type=refresh_token.
  4. If response contains "invalid_grant":
       stderr "Refresh token rejected. Re-run setup.sh.", exit 3.
  5. Atomically update credentials.json with new access_token and
     expires_at = now + expires_in.
  6. echo new access_token.
```

**Security invariants:**
- Tokens never written to stdout except as the function's single return value.
- Tokens never logged to stderr.
- File permission verified/reset to `600` on every write.

## 6. Operation scripts

### 6.1 `upload.sh <local_path> <dropbox_path>`

1. Validate `local_path` exists and is readable; else exit 1.
2. `size=$(stat -c %s "$local_path")`.
3. `token=$(get_access_token)`.
4. Branch on size:
   - **≤ 150 MB:** `POST https://content.dropboxapi.com/2/files/upload`
     with header `Dropbox-API-Arg: {"path":"<dropbox_path>","mode":"overwrite","autorename":false,"mute":false}`,
     body = file contents.
   - **> 150 MB:** upload session (8 MB chunks)
     - `POST /2/files/upload_session/start` with first chunk → `session_id`.
     - Loop: `POST /2/files/upload_session/append_v2` with `{"cursor":{"session_id","offset"},"close":false}`.
     - Final: `POST /2/files/upload_session/finish` with
       `{"cursor":{...},"commit":{"path":"<dropbox_path>","mode":"overwrite"}}`.
5. Print a one-line JSON summary: `{"path":..., "size":..., "content_hash":...}`.

**Chunking:** `dd if=<file> bs=8M skip=<n> count=1` piped to `curl --data-binary @-`.
**Progress:** chunked path writes `[k/N] uploading chunk...` lines to stderr.

### 6.2 `download.sh <dropbox_path> [<local_path>]`

1. `token=$(get_access_token)`.
2. If `local_path` omitted: `local_path=$(basename "$dropbox_path")` in CWD.
3. If `local_path` already exists: exit 1 with message
   `File exists: <path>. Remove it or specify a different destination.`
4. `POST https://content.dropboxapi.com/2/files/download`
   with header `Dropbox-API-Arg: {"path":"<dropbox_path>"}`, `--output <local_path>`.
5. HTTP 409 with `path/not_found` → exit 4 `Not found: <dropbox_path>`.
6. On success: print the saved path on stdout.

**Rationale for non-overwrite default:** downloads risk destroying local work-in-progress; safer to require explicit user action.

### 6.3 `share.sh <dropbox_path>`

1. `token=$(get_access_token)`.
2. `POST /2/sharing/create_shared_link_with_settings` with body
   `{"path":"<dropbox_path>","settings":{"requested_visibility":"public","audience":"public","access":"viewer"}}`.
3. Branch on response:
   - **200 OK:** extract `.url`.
   - **409 `shared_link_already_exists`:** `POST /2/sharing/list_shared_links`
     with `{"path":"<dropbox_path>","direct_only":true}` → `.links[0].url`.
   - **409 `path/not_found`:** exit 4.
   - **Other error:** dump raw response to stderr, exit 5.
4. Print URL on stdout (as-is; `?dl=0` preview form — user can post-process if they want `?dl=1`).

### 6.4 Shared helper (`auth.sh`)

```
api_call <endpoint> <json_body>:
  curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "$json_body" "$endpoint"
  On HTTP error: stderr dump + exit.
```

## 7. Error handling policy

| Condition | Exit code | Behavior |
|---|---|---|
| Missing `credentials.json` | 2 | stderr "Run setup.sh first" |
| `invalid_grant` from refresh | 3 | stderr "Refresh token rejected. Re-run setup.sh." |
| `path/not_found` | 4 | stderr "Not found: <path>" |
| Other API error | 5 | Raw response dumped to stderr |
| Network/curl failure | curl's exit code | stderr = curl's stderr |
| Missing `jq`/`curl` | 127 | stderr "jq and curl required" |
| Local file invalid (upload) | 1 | stderr "Cannot read <path>" |
| Local file already exists (download) | 1 | stderr "File exists: <path>" |

All scripts: on non-zero exit, Claude must surface stderr verbatim to the user (codified in `SKILL.md`). No automatic retries on auth errors.

## 8. Testing

### 8.1 Unit tests (mocked, run on every commit)

Location: `skills/cc-dropbox/scripts/test/`.

Approach: override `curl` as a shell function that returns fixture responses. No bats dependency — plain-bash `run_tests.sh` runner.

Cases:
- **`test_auth.sh`**
  - Cached token still valid → no refresh call.
  - Cached token expired → refresh called, credentials.json updated.
  - `invalid_grant` response → exit 3.
  - Missing credentials.json → exit 2.
- **`test_upload.sh`**
  - 150 MB boundary: ≤ threshold takes single-shot path; > threshold takes session path.
  - Missing/unreadable local file → exit 1.
- **`test_share.sh`**
  - 200 response → URL extracted.
  - 409 `shared_link_already_exists` → falls back to `list_shared_links`, returns existing URL.
  - 409 `path/not_found` → exit 4.

### 8.2 Integration test (manual, gated)

`scripts/test/integration.sh`, runs only when `DROPBOX_INTEGRATION_TEST=1`:

1. Create a temp file; `upload.sh` to `/cc-dropbox-test/small.bin`.
2. `download.sh` it back; compare `content_hash`.
3. `share.sh` the path; `curl -I` the returned URL expects HTTP 200.
4. Generate a 200 MB file; `upload.sh` (exercises chunked path).
5. Cleanup: delete both test files from Dropbox via `/2/files/delete_v2`.

Not run in CI.

## 9. `SKILL.md` structure

```markdown
---
name: cc-dropbox
description: Upload files to Dropbox, download from Dropbox, and create/retrieve shared links. Use when the user mentions Dropbox, asks to upload/download/share a file via Dropbox, or wants a shareable link for a file already in their Dropbox.
---

# cc-dropbox

Dropbox file operations via Dropbox HTTP API v2.

## When to use
- "upload X to Dropbox" → scripts/upload.sh <local> <dropbox>
- "download X from Dropbox" → scripts/download.sh <dropbox> [<local>]
- "share link for X" / "Dropbox link" → scripts/share.sh <dropbox>
- "set up Dropbox" OR credentials missing → scripts/setup.sh

## Prerequisites
Before upload/download/share, verify ~/.config/cc-dropbox/credentials.json exists.
If missing: tell the user "Dropbox is not set up yet. Run setup first?" and await confirmation.

## Path rules
Dropbox paths MUST start with `/`. Reject relative paths.

## Error surfacing
If a script exits non-zero, show its stderr verbatim. Never retry auth failures automatically.
```

Trigger keywords in `description` (Dropbox, upload, download, shared link) are the sole basis for Claude's skill-selection decision, so they must appear naturally.

## 10. Dependencies

- `curl` (HTTP)
- `jq` (JSON parse/build)
- `stat`, `dd`, `mktemp` (coreutils, assumed present)

`setup.sh` verifies `curl` and `jq` at startup and exits 127 with a clear message if missing.

## 11. `plugin.json`

```json
{
  "name": "cc-dropbox",
  "version": "0.1.0",
  "description": "Dropbox file operations (upload/download/share) for Claude Code",
  "author": "axect"
}
```

## 12. Out of scope (YAGNI)

- Folder-level operations (list, create, delete folders)
- File move/rename/delete
- Team/workspace features
- Password-protected or time-limited share links (left as future config)
- Progress bars beyond a stderr line per chunk
- Retry-with-backoff (user re-invokes on transient failure)
