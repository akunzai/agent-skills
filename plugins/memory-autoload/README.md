# memory-autoload

A Claude Code and Codex plugin that loads durable long-term memory into context
at the start of every session, and nudges the agent to run the memory-management
skills.

## What it does

On `SessionStart`:

- **`load-memory.sh`** (matchers `startup|resume|clear|compact`) prints
  `~/.agents/MEMORY.md` to stdout, which the agent adds to the session context.
  If the file is missing or empty, it is a silent no-op.
- **`nudge-memory-skills.sh`** (matchers `startup|resume`) injects a one-line
  instruction asking the agent to run the `mem-sync` skill (pull other devices'
  memory logs) and then `mem-auto` (resume handoffs, capture candidates).

Hooks cannot invoke skills directly, so the nudge is a soft trigger: the agent
decides whether to act, and it is a no-op if the `mem-*` skills are not installed.
This plugin does not install those skills; install them separately with
`npx skills add akunzai/agent-skills`.

## Configuration

- `MEMORY_FILE` — override the memory file path (default `~/.agents/MEMORY.md`).
  Used mainly for testing.

## Install

### Claude Code

```bash
/plugin marketplace add akunzai/agent-skills
/plugin install memory-autoload@akunzai
```

### Codex

```bash
codex plugin marketplace add akunzai/agent-skills
```

Then open `/plugins`, select the `akunzai agent skills` marketplace, and install
`memory-autoload`.

## Compatibility

- Claude Code: supported via `.claude-plugin/marketplace.json` and
  `plugins/memory-autoload/.claude-plugin/plugin.json`.
- Codex: supported via `.agents/plugins/marketplace.json` and
  `plugins/memory-autoload/.codex-plugin/plugin.json`.
- OpenCode: `SKILL.md` discovery is compatible with agent skills, but this
  session-start hook plugin is not packaged for OpenCode.
- Antigravity CLI: uses a separate root `plugin.json` layout, which is not
  included in this plugin.
