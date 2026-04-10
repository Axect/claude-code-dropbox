# claude-code-dropbox

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](CHANGELOG.md)
[![Tests](https://img.shields.io/badge/tests-88%20passing-brightgreen.svg)](skills/cc-dropbox/scripts/test/)

A Claude Code plugin that unifies Dropbox file operations — **upload**, **download**, and **shared link** — into one skill. Claude invokes bash scripts in response to natural-language requests like "upload this PDF to Dropbox" or "make a share link for `/Papers/draft.pdf`".

## TL;DR

```bash
# 1. Install as a Claude Code plugin (see Installation below)
# 2. One-time setup: register a Dropbox app, then run:
bash skills/cc-dropbox/scripts/setup.sh
# 3. Talk to Claude:
#    "Upload this PDF to /Papers/report.pdf on Dropbox"
#    "Make a share link for /Papers/report.pdf"
```

## Why this plugin?

Dropbox's own CLI is feature-rich but heavy for the common case of "push a file, get a link." This plugin gives Claude Code a minimal, auditable bash-only path for the three operations that come up most often in research and writing workflows:

- You stay in your editor — no context switch to a browser or GUI client.
- Claude handles the phrasing (path resolution, reusing existing share links, picking upload strategy by file size).
- The implementation is ~500 lines of bash you can read in one sitting. Nothing hides behind a runtime.
- Credentials live in `~/.config/cc-dropbox/credentials.json` (`chmod 600`), refreshed on demand via OAuth2. No long-lived tokens.

## Features

- **Upload** files of any size — automatic chunked upload session for files > 150 MB (8 MB chunks)
- **Download** files with overwrite protection, dangling-symlink safety, and parent-directory validation
- **Shared link** create or reuse — automatically falls back to `list_shared_links` when Dropbox reports the link already exists
- **OAuth2 refresh-token flow** with on-demand access-token caching and atomic credentials rewrite
- **Zero runtime dependencies** beyond `curl` and `jq`
- **88 unit assertions** running fully offline against a mocked `curl`

## Requirements

- `bash` (4.0+), `curl`, `jq`
- Standard coreutils (`stat`, `dd`, `mktemp`, `sha256sum`)
- A Dropbox account
- A registered Dropbox app (see [Setup](#setup-one-time))

## Installation

Install as a Claude Code plugin from the GitHub repo:

```
/plugin install Axect/claude-code-dropbox
```

Claude will pick up `skills/cc-dropbox/SKILL.md` automatically.

Alternatively, clone the repo and source the scripts directly:

```bash
git clone https://github.com/Axect/claude-code-dropbox.git
cd claude-code-dropbox
bash skills/cc-dropbox/scripts/setup.sh
```

## Setup (one time)

1. Go to <https://www.dropbox.com/developers/apps> and click **Create app**.
2. Choose:
   - **API:** Scoped access
   - **Access type:** Full Dropbox
   - **Name:** anything (e.g. `claude-code-skill`)
3. On the app page, open the **Permissions** tab and enable:
   - `files.content.write`
   - `files.content.read`
   - `sharing.write`
   - `sharing.read`

   Click **Submit**.
4. Note the **App key** and **App secret** from the Settings tab.
5. Run the setup script:

   ```bash
   bash skills/cc-dropbox/scripts/setup.sh
   ```

   Or just tell Claude: *"set up Dropbox"*.

   The script will:
   - Prompt for your app key and app secret (secret is hidden).
   - Print a URL to open in a browser for OAuth authorization.
   - Prompt you to paste the authorization code Dropbox displays.
   - Exchange the code for an access + refresh token and save them to `~/.config/cc-dropbox/credentials.json` (`chmod 600`).

## Usage (via Claude)

Just talk to Claude:

- *"Upload `./report.pdf` to `/Papers/report.pdf` in Dropbox."*
- *"Download `/Papers/draft.pdf` from Dropbox."*
- *"Make a share link for `/Papers/draft.pdf`."*

Claude reads `skills/cc-dropbox/SKILL.md`, picks the right script, and surfaces the output.

## Usage (direct)

You can also call the scripts directly from a shell:

```bash
bash skills/cc-dropbox/scripts/upload.sh   ./report.pdf   /Papers/report.pdf
bash skills/cc-dropbox/scripts/download.sh /Papers/draft.pdf
bash skills/cc-dropbox/scripts/share.sh    /Papers/draft.pdf
```

### Example output

**Upload** prints a one-line JSON summary on success:

```
$ bash skills/cc-dropbox/scripts/upload.sh ./report.pdf /Papers/report.pdf
{"path":"/Papers/report.pdf","size":184523,"content_hash":"9f86d081884c7d65..."}
```

**Download** prints the saved local path:

```
$ bash skills/cc-dropbox/scripts/download.sh /Papers/draft.pdf
draft.pdf
```

**Share** prints the URL (preview form — swap `?dl=0` → `?dl=1` for direct download):

```
$ bash skills/cc-dropbox/scripts/share.sh /Papers/draft.pdf
https://www.dropbox.com/scl/fi/abc123/draft.pdf?dl=0
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `cc-dropbox: no credentials. Run setup.sh first.` | `~/.config/cc-dropbox/credentials.json` missing | `bash skills/cc-dropbox/scripts/setup.sh` |
| `cc-dropbox: refresh token rejected. Re-run setup.sh.` | Refresh token revoked or app permissions changed | Re-run setup.sh |
| `cc-dropbox: dropbox path must start with '/'` | Gave a relative Dropbox path | Use an absolute path like `/Papers/file.pdf` |
| `cc-dropbox: File exists: <path>` (download) | Local file or symlink already present | Remove it or pass a different destination |
| `cc-dropbox: Not found: <path>` | Dropbox path doesn't exist | Verify the path in the Dropbox web UI |
| `cc-dropbox: 'jq' is required but not found.` | Missing dependency | Install `jq` (e.g. `sudo apt install jq` / `brew install jq`) |

All errors go to stderr with a `cc-dropbox:` prefix. Exit codes:

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad argument or local filesystem error |
| 2 | Credentials missing (run `setup.sh`) |
| 3 | Refresh token rejected (re-run `setup.sh`) |
| 4 | Dropbox path not found |
| 5 | Other API error |
| 64 | Usage error |
| 127 | Missing dependency (`curl`/`jq`) |

## Security

- Credentials are stored at `~/.config/cc-dropbox/credentials.json` with `chmod 600`.
- Access tokens are refreshed on demand; only the refresh token persists at rest.
- Credentials writes are atomic (same-directory `mktemp` + `mv`) so an interrupt can't corrupt the file.
- Refresh responses are validated before being written — malformed JSON or missing fields never replace a good credentials file.
- `.gitignore` excludes all `credentials*` and `.env*` files from ever being committed.
- **Known limitation:** `client_secret` is passed to `curl` via argv, briefly visible in `/proc/<pid>/cmdline` on multi-user systems. Acceptable for personal use; see `TODO(security)` comments in `auth.sh` and `setup.sh`.

## Testing

Unit tests (mocked `curl`) run offline with no network or credentials:

```bash
bash skills/cc-dropbox/scripts/test/run_tests.sh
```

Expected: `TOTAL: pass=88 fail=0`.

Integration test (hits real Dropbox, requires a configured `credentials.json`):

```bash
DROPBOX_INTEGRATION_TEST=1 bash skills/cc-dropbox/scripts/test/integration.sh
```

The integration script uploads a small file, downloads it and verifies the hash, creates and reuses a share link, and exercises the chunked upload path with a 200 MB file. It cleans up its own test files on exit.

## Contributing

Contributions welcome — issues and PRs both.

- Follow **Gitflow**: branch off `dev`, PR back into `dev`, release via `dev` → `main` merge.
- Write **TDD**: failing test → minimal implementation → passing test → commit. Each feature/fix should add at least one test case that would fail on the previous commit.
- Keep scripts **focused** — `auth.sh` is the only sourceable library; each operation script stays single-file.
- Run the full suite before opening a PR:
  ```bash
  bash skills/cc-dropbox/scripts/test/run_tests.sh
  ```
- Commit messages follow conventional prefixes: `feat(scope):`, `fix(scope):`, `test(scope):`, `docs:`, `chore:`.

## License

MIT — see [LICENSE](LICENSE).
