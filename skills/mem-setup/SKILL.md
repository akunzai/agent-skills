---
name: mem-setup
description: Wire each installed coding agent's native global memory file to one canonical ~/.agents/AGENTS.md, so Claude Code, Codex, OpenCode, Antigravity/Gemini, and pi all read the same durable cross-agent memory. Use to set up or refresh global memory bridging across agents.
---

# mem-setup — Cross-Agent Global Memory Bridge

Points every installed agent's global memory at a single canonical core file so
durable instructions are shared across agents. Ships the wiring only — you supply
the content of `~/.agents/AGENTS.md` (and any augmentation modules).

## Canonical layout (user-owned)

- `~/.agents/AGENTS.md` — the cross-agent **core**, the single source of truth.
- Optional augmentation modules — extra rules inlined for agents with weak
  hook/skill support. Pass their paths via `MEM_SETUP_AUGMENT` (colon-separated).
  The repo ships none.

## Per-agent bridge

| Agent | Native global path | Tier | Method |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` | high (core) | `@import` |
| Codex | `~/.codex/AGENTS.md` | high (core) | symlink (copy on Windows) |
| pi | `~/.pi/agent/AGENTS.md` | high (core) | symlink (copy on Windows) |
| Antigravity / Gemini | `~/.gemini/GEMINI.md` | low (core + augment) | `@import` |
| OpenCode | `~/.config/opencode/opencode.json` | low (core + augment) | `instructions[]` |

High-tier agents get dynamic behaviors from plugins, so they read the **core**
only. Low-tier agents have weak hook support, so augmentation modules are
composed into their static prompt via import / config — never by duplicating a
file.

Gemini's `@import` method degrades to a plain symlink when there's nothing to
compose (no `MEM_SETUP_AUGMENT`) and the target is missing or already a
symlink — same effect, but skips depending on the target agent's own import
resolution. A configured augment module always keeps the append-import
behavior (a symlink can't reference two files). An existing real `GEMINI.md`
keeps it too, *unless* its bytes exactly match this script's own prior stub
output (no augment) — that case is self-healed into a symlink (after a
backup), since it holds no manual content to preserve. This only applies to
the low tier — Claude Code's own `import` bridge always stays an `@import`
stub, never a symlink.

OpenCode's `config` method edits `instructions[]` in JSON: it prefers `jq`
(the tool this repo's `mise.toml` pins), falls back to `python3` if `jq` is
absent, and otherwise prints the paths to add manually. Neither is a hard
requirement.

## Workflow (always dry-run first)

1. Ensure `~/.agents/AGENTS.md` exists (your durable cross-agent instructions).
2. Run the read-only plan and show it to the user:
   `bash skills/mem-setup/scripts/mem-setup-bridge.sh plan`
3. After **explicit user confirmation**, apply:
   `bash skills/mem-setup/scripts/mem-setup-bridge.sh apply`

Override the core path with `MEM_SETUP_CANONICAL` and augmentation modules with
`MEM_SETUP_AUGMENT` (colon-separated absolute paths).

## Safety

- Only acts on **installed** agents (those whose config directory exists).
- **Never write through a symlink** — an existing symlink is removed first, so the
  canonical core is never clobbered.
- Real files are backed up to `*.bak-<timestamp>` before any change.
- **Idempotent** — re-running makes no changes once bridged.
- Windows (Git Bash): import/config methods need no symlink; for Codex/pi the
  script falls back to a copy and warns that you must re-run to refresh.

## Migration from `memory-autoload`

This skill replaces the retired `memory-autoload` plugin and its
`~/.agents/MEMORY.md`. If that plugin is still installed, remove it; if
`~/.agents/MEMORY.md` holds content, merge it into `~/.agents/AGENTS.md` first.
