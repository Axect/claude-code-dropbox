# dropbox-skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](CHANGELOG.md)
[![Tests](https://img.shields.io/badge/tests-88%20passing-brightgreen.svg)](scripts/test/)

A portable Dropbox skill for AI agents that turns natural-language requests into three dependable operations: **upload a file**, **download a file**, and **create or reuse a shared link**.

It follows the Agent Skills directory format, so the same repository can be installed in Forge, Claude Code, and other compatible clients that can read `SKILL.md` and run bundled bash scripts.

## TL;DR

```bash
# Install as a skill directory
mkdir -p ~/.forge/skills
ln -s /path/to/dropbox-skill ~/.forge/skills/dropbox-skill

# One-time Dropbox OAuth setup
bash scripts/setup.sh

# Then ask your agent things like:
# - "Upload ./report.pdf to /Papers/report.pdf in Dropbox"
# - "Make a shared link for /Papers/report.pdf"
```

## Why this skill?

Dropbox's official tooling is powerful, but often heavier than the common agent workflow of "put this file in Dropbox" or "give me a link I can share." This skill keeps that path small, readable, and portable:

- **Natural-language friendly** — the agent maps user intent to upload, download, or share operations.
- **Portable by design** — one `SKILL.md`, one `scripts/` directory, no framework lock-in.
- **Auditable implementation** — the behavior lives in bash scripts you can inspect end to end.
- **Practical auth model** — credentials live in `~/.config/dropbox-skill/credentials.json` with refresh-token based access-token renewal.
- **Backwards compatible** — legacy credentials at `~/.config/cc-dropbox/credentials.json` are still accepted if present.

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

This repository is packaged as a standard Agent Skills directory: the repository root is the skill directory, `SKILL.md` is the entrypoint, and the bundled scripts live in `scripts/`.

Choose the install style that matches your agent.

### Forge user-level install

```bash
mkdir -p ~/forge/skills
cd ~/forge/skills
git clone https://github.com/Axect/dropbox-skill.git
```

Forge will discover the skill at `~/forge/skills/dropbox-skill/SKILL.md`.

### Claude Code personal install

```bash
mkdir -p ~/.claude/skills
cd ~/.claude/skills
git clone https://github.com/Axect/dropbox-skill.git
```

Claude Code will discover the skill at `~/.claude/skills/dropbox-skill/SKILL.md`.

### Project-local install

```bash
mkdir -p .claude/skills
git clone https://github.com/Axect/dropbox-skill.git .claude/skills/dropbox-skill
```

### Other Agent Skills-compatible clients

Copy or clone this repository so the skill directory itself is named `dropbox-skill` and contains `SKILL.md` at its root.

```text
dropbox-skill/
├── SKILL.md
├── scripts/
└── LICENSE
```

If your client supports the Agent Skills open standard, point it at that directory or place it inside the client's configured skills folder.

## Setup (one time)

1. Go to <https://www.dropbox.com/developers/apps> and click **Create app**.
2. Choose:
   - **API:** Scoped access
   - **Access type:** Full Dropbox
   - **Name:** anything (e.g. `dropbox-skill-demo`)
3. On the app page, open the **Permissions** tab and enable:
   - `files.content.write`
   - `files.content.read`
   - `sharing.write`
   - `sharing.read`

   Click **Submit**.
4. Note the **App key** and **App secret** from the Settings tab.
5. Run the setup script:

   ```bash
   bash scripts/setup.sh
   ```

   Or just tell your agent: *"set up Dropbox"*.

   The script will:
   - Prompt for your app key and app secret (secret is hidden).
   - Print a URL to open in a browser for OAuth authorization.
   - Prompt you to paste the authorization code Dropbox displays.
   - Exchange the code for an access + refresh token and save them to `~/.config/dropbox-skill/credentials.json` (`chmod 600`).

## Usage (via an agent)

Ask any compatible agent in natural language:

- *"Upload `./report.pdf` to `/Papers/report.pdf` in Dropbox."*
- *"Download `/Papers/draft.pdf` from Dropbox."*
- *"Make a share link for `/Papers/draft.pdf`."*
- *"Download `/Research/data.tar.zst` from Dropbox to `./data.tar.zst`."*

The agent reads `SKILL.md`, chooses the right script, and returns the result.

## Usage (direct)

You can also call the scripts directly from a shell:

```bash
bash scripts/upload.sh   ./report.pdf   /Papers/report.pdf
bash scripts/download.sh /Papers/draft.pdf
bash scripts/share.sh    /Papers/draft.pdf
```

### Example output

**Upload** prints a one-line JSON summary on success:

```
$ bash scripts/upload.sh ./report.pdf /Papers/report.pdf
{"path":"/Papers/report.pdf","size":184523,"content_hash":"9f86d081884c7d65..."}
```

**Download** prints the saved local path:

```
$ bash scripts/download.sh /Papers/draft.pdf
draft.pdf
```

**Share** prints the URL (preview form — swap `?dl=0` → `?dl=1` for direct download):

```
$ bash scripts/share.sh /Papers/draft.pdf
https://www.dropbox.com/scl/fi/abc123/draft.pdf?dl=0
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `dropbox-skill: no credentials. Run setup.sh first.` | `~/.config/dropbox-skill/credentials.json` missing | `bash scripts/setup.sh` |
| `dropbox-skill: refresh token rejected. Re-run setup.sh.` | Refresh token revoked or app permissions changed | Re-run setup.sh |
| `dropbox-skill: dropbox path must start with '/'` | Gave a relative Dropbox path | Use an absolute path like `/Papers/file.pdf` |
| `dropbox-skill: File exists: <path>` (download) | Local file or symlink already present | Remove it or pass a different destination |
| `dropbox-skill: Not found: <path>` | Dropbox path doesn't exist | Verify the path in the Dropbox web UI |
| `dropbox-skill: 'jq' is required but not found.` | Missing dependency | Install `jq` (e.g. `sudo apt install jq` / `brew install jq`) |

All errors go to stderr with a `dropbox-skill:` prefix. Exit codes:

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

- Credentials are stored at `~/.config/dropbox-skill/credentials.json` with `chmod 600`.
- Access tokens are refreshed on demand; only the refresh token persists at rest.
- Credentials writes are atomic (same-directory `mktemp` + `mv`) so an interrupt can't corrupt the file.
- Refresh responses are validated before being written — malformed JSON or missing fields never replace a good credentials file.
- `.gitignore` excludes all `credentials*` and `.env*` files from ever being committed.
- **Known limitation:** `client_secret` is passed to `curl` via argv, briefly visible in `/proc/<pid>/cmdline` on multi-user systems. Acceptable for personal use; see `TODO(security)` comments in `auth.sh` and `setup.sh`.

## Testing

Unit tests (mocked `curl`) run offline with no network or credentials:

```bash
bash scripts/test/run_tests.sh
```

Expected: `TOTAL: pass=88 fail=0`.

Integration test (hits real Dropbox, requires a configured `credentials.json` in the new config path or the legacy fallback path):

```bash
DROPBOX_INTEGRATION_TEST=1 bash scripts/test/integration.sh
```

The integration script uploads a small file, downloads it and verifies the hash, creates and reuses a share link, and exercises the chunked upload path with a 200 MB file. It cleans up its own test files on exit.

## Contributing

Contributions welcome — issues and PRs both.

- Follow **Gitflow**: branch off `dev`, PR back into `dev`, release via `dev` → `main` merge.
- Write **TDD**: failing test → minimal implementation → passing test → commit. Each feature/fix should add at least one test case that would fail on the previous commit.
- Keep scripts **focused** — `auth.sh` is the only sourceable library; each operation script stays single-file.
- Run the full suite before opening a PR:
  ```bash
  bash scripts/test/run_tests.sh
  ```
- Commit messages follow conventional prefixes: `feat(scope):`, `fix(scope):`, `test(scope):`, `docs:`, `chore:`.

## License

MIT — see [LICENSE](LICENSE).
