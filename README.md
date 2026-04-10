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
