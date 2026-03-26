# Changelog

## v0.12.1 (2026-03-26)

### Bug Fixes
- Fix PyPI package missing Info.plist — pip install users could not compile Swift app locally (#14)
- Fix version mismatch: `__init__.__version__` and Swift `fallbackVersion` now sync with pyproject.toml
- Add `Info.plist` to `[tool.setuptools.package-data]` so it's included in wheel

## v0.12.0 (2026-03-26)

### New Features
- Session completion notification — macOS system notification when Claude Code tasks finish
- Cost alert notification — daily cost threshold warning with configurable limits
- Permission request notification — notify when Claude Code awaits user permission
- Smart notification suppression — auto-suppress when app window is focused
- Webhook support — send notifications to custom HTTP endpoints
- Hooks installation support (`cc-stats-hooks` CLI entry point)

## v0.11.0 (2026-03-25)

### New Features
- Add background version update checker with local cache (CLI, macOS app, web dashboard)
- Display update hint on CLI startup (cache-only, non-blocking)

### Bug Fixes
- Respect `$CODEX_HOME` env var in CodexParser (#5)

### Performance
- Split data loading from filtering + single-pass daily stats (#6)

### Refactoring
- Invalidate cache on refresh to load new session data (#12)

### Documentation
- Add security and performance review guidelines to CLAUDE.md
