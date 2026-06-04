# memory-autoload

A Claude Code plugin that loads durable long-term memory into context at the
start of every session, and nudges the agent to run the memory-management skills.

## What it does

On `SessionStart`:

- **`load-memory.sh`** (matchers `startup|resume|clear|compact`) prints
  `~/.agents/MEMORY.md` to stdout, which Claude Code adds to the session context.
  If the file is missing or empty, it is a silent no-op.
- **`nudge-memory-skills.sh`** (matchers `startup|resume`) injects a one-line
  instruction asking the agent to run the `mem-sync` skill (pull other devices'
  memory logs) and then `mem-auto` (resume handoffs, capture candidates).

Hooks cannot invoke skills directly, so the nudge is a soft trigger: the agent
decides whether to act, and it is a no-op if the `mem-*` skills are not installed.

## Configuration

- `MEMORY_FILE` — override the memory file path (default `~/.agents/MEMORY.md`).
  Used mainly for testing.

## Install

```bash
/plugin marketplace add akunzai/agent-skills
/plugin install memory-autoload@akunzai
```
