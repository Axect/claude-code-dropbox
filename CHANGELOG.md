# Changelog

## [0.1.0] - 2026-04-13

### Added
- Initial `dropbox-skill` package release with Agent Skills entrypoint `SKILL.md` and bundled Dropbox operation scripts
- `scripts/auth.sh`: OAuth2 refresh-token flow with access-token caching, atomic credentials rewrite, response validation, and `api_call` helper
- `scripts/setup.sh`: interactive one-time OAuth2 bootstrap (`exchange_code`) with mv-guard and empty-input validation
- `scripts/upload.sh`: single-shot upload (≤150MB) and chunked upload session (>150MB, 8MB chunks, env-overridable)
- `scripts/download.sh`: download with no-overwrite guard, symlink safety, parent-dir validation, and 404 detection
- `scripts/share.sh`: create shared link with public viewer access; reuses existing link via `list_shared_links` on `shared_link_already_exists`
- `scripts/test/`: bash unit test runner with mocked `curl`, file-based args/call recording, early-exit detection, tmp cleanup
- `scripts/test/integration.sh`: gated end-to-end integration script (requires `DROPBOX_INTEGRATION_TEST=1`)
- `README.md` with installation, setup, usage, and security notes

### Changed
- Repackaged the repository as a portable Agent Skills skill rooted at `SKILL.md`
- Polished the README with clearer positioning, Forge installation guidance, and updated repository URLs
- Renamed the public skill/package identity from `cc-dropbox` to `dropbox-skill`
- Switched the default credentials path to `~/.config/dropbox-skill/credentials.json` with fallback support for the legacy `~/.config/cc-dropbox/credentials.json`

### Test coverage
- 88 unit assertions across 7 test files, all passing offline with mocked curl
