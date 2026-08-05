# Cross-Agent Global Memory Locations

Each installed coding agent reads its own native global memory file from a
different path. There is no automation for this — when asked to wire an agent
up, point its native file at the canonical core below however fits that
file's format (symlink, import line, config array, etc.).

## Canonical core

`~/.agents/AGENTS.md` — the cross-agent single source of truth.

## Per-agent native path

| Agent | Native global path | Docs |
| --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` | [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory) |
| Codex | `~/.codex/AGENTS.md` | [developers.openai.com/codex/guides/agents-md](https://developers.openai.com/codex/guides/agents-md) |
| pi | `~/.pi/agent/AGENTS.md` | — |
| Antigravity / Gemini | `~/.gemini/GEMINI.md` | [geminicli.com/docs/cli/gemini-md.md](https://geminicli.com/docs/cli/gemini-md.md) |
| OpenCode | `~/.config/opencode/opencode.json` | [opencode.ai/docs/rules](https://opencode.ai/docs/rules/) |

If the agent isn't listed above, look up its own docs (or search `<agent name>
global memory file location / config`) to find the real native path before
wiring it — never guess.
