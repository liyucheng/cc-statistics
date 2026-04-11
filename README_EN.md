# cc-statistics

[![PyPI](https://img.shields.io/pypi/v/cc-statistics?color=blue)](https://pypi.org/project/cc-statistics/)
[![Downloads](https://img.shields.io/pypi/dm/cc-statistics?color=green)](https://pypi.org/project/cc-statistics/)
[![GitHub stars](https://img.shields.io/github/stars/androidZzT/cc-statistics?style=social)](https://github.com/androidZzT/cc-statistics)
[![License](https://img.shields.io/github/license/androidZzT/cc-statistics)](LICENSE)

English | [中文](README.md)

**The only AI coding usage tracker that covers Claude Code, Gemini CLI, Codex CLI, and Cursor — in one native macOS app.**

Track tokens, costs, sessions, and tool calls across all your AI coding tools. Everything runs locally; nothing leaves your machine.

```bash
uv tool install cc-statistics
cc-stats --all --since 7d   # all platforms, last 7 days
cc-stats-app                # launch macOS menu-bar app
```

---

## Platform Support

| Feature | cc-statistics | phuryn/claude-usage | ccflare |
|---------|:---:|:---:|:---:|
| Claude Code | Yes | Yes | Yes |
| Gemini CLI | Yes | No | No |
| Codex CLI | Yes | No | No |
| Cursor | Yes | No | No |
| Native macOS app | Yes | No | No |
| Session search + resume | Yes | No | No |
| Pixel-art status bar mascot | Yes | No | No |
| Slack / Feishu / DingTalk Webhook | Yes | No | No |
| Zero dependencies | Yes | No | No |

---

## macOS App

<img src="docs/desktop_now.png" width="520" alt="cc-statistics macOS Menu Bar App — dark theme dashboard with token and cost stats">

Native SwiftUI panel. Pre-built binary — no local compilation required.

- Status bar: Claude logo + today's tokens + cost; turns red when over limit
- Right-click to switch display mode (Token+Cost / Token / Cost / Sessions)
- Global hotkey `Cmd+Shift+C`

### Clawd Status Bar Animation

A pixel-art Clawd mascot in the status bar reacts to AI work state in real time:

<img src="docs/clawd-states.png" width="600" alt="Clawd Animation States">

---

## CLI Demo

<img src="docs/demo.gif" width="600" alt="CC Stats CLI Demo">

---

## Installation

```bash
# uv (recommended)
uv tool install cc-statistics

# pipx
pipx install cc-statistics

# Homebrew (macOS / Linux)
brew install androidZzT/tap/cc-statistics
```

Zero dependencies — Python stdlib only.

---

## Key Features

- **Multi-Source** — Claude Code, Gemini CLI, Codex, Cursor — switch or aggregate stats across all sources
- **macOS Native Menu Bar** — Pre-built binary; Claude logo + Token + Cost, turns red when over limit
- **Cost Estimation** — Built-in pricing for Opus / Sonnet / Haiku / Gemini 2.5 Pro / Flash / GPT-4o
- **Usage Alerts** — Daily/weekly cost limits with system notifications when exceeded
- **Session Search / Resume / Export** — Search past conversations by keyword, one-click resume command, export Markdown / share as image
- **Weekly / Monthly Reports** — Auto-generate Markdown reports, push to Feishu / DingTalk / Slack via Webhook
- **Multi-dimensional Stats** — Instructions, Tool calls Top 10, AI vs User time, Code changes (by language), Tokens (by model)
- **100% Local** — All data read from local files, nothing sent over the network
- **Bilingual** — Auto-follows system language, supports manual Chinese / English switch

---

## Usage

### CLI (All Platforms)

```bash
cc-stats                     # Analyze current directory sessions
cc-stats --list              # List all projects (Claude + Gemini + Codex + Cursor)
cc-stats --all --since 3d    # Last 3 days, all projects
cc-stats sailor --last 3     # Last 3 sessions for a project
cc-stats --report week       # Generate weekly report (Markdown)
cc-stats --compare --since 1w # Compare projects (last week)
cc-stats --notify https://hooks.slack.com/services/xxx  # Webhook push
```

### Web Dashboard (All Platforms)

```bash
cc-stats-web
```

Auto-opens browser with a dark-themed statistics dashboard.

### macOS Menu Bar Panel

```bash
cc-stats-app
```

**Dashboard Panel (Native SwiftUI):**
- Multi-source: Claude Code / Gemini CLI / Codex / Cursor, switch or aggregate
- Theme: Follow System / Dark / Light
- Usage alerts: daily/weekly cost limits with system notifications
- Export stats to JSON / CSV (auto-saves to Desktop)
- Settings: Launch at login, language switch, theme, version update check
- Session search + one-click resume (`claude --resume`)
- Process manager: view all Claude process memory usage
- Tool call breakdown: Skill and MCP tools expanded to specific names

---

## Data Sources

All data is read from local files. Nothing is sent over the network.

| Source | Path |
|--------|------|
| Claude Code | `~/.claude/projects/<project>/<session>.jsonl` |
| Gemini CLI | `~/.gemini/tmp/<project>/chats/<session>.json` |
| Codex | `~/.codex/sessions/*.jsonl` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Git Changes | `git log --numstat` in project directory |

---

## Acknowledgments

Status bar Clawd animation sprites from [clawd-on-desk](https://github.com/rullerzhou-afk/clawd-on-desk) — an Electron desktop pet that senses AI coding agent state via hooks and plays pixel-art animations.

---

## Support

If cc-statistics saves you money on your AI coding bills, consider [sponsoring](https://github.com/sponsors/androidZzT) the project.
