# memory-autoload

A Claude Code and Codex plugin that loads durable long-term memory into context
at the start of every session.

## What it does

On `SessionStart`:

- **`load-memory.sh`** (matchers `startup|resume|clear|compact`) prints
  `~/.agents/MEMORY.md` to stdout, which the agent adds to the session context.
  If the file is missing or empty, it is a silent no-op.

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

On Windows, make sure `bash` is available on `PATH` before starting Codex. Git for
Windows usually provides it at `C:\Program Files\Git\bin`; add that directory to
`PATH` so session hooks can run.

## Compatibility

- Claude Code: supported via `.claude-plugin/marketplace.json` and
  `plugins/memory-autoload/.claude-plugin/plugin.json`.
- Codex: supported via `.agents/plugins/marketplace.json` and
  `plugins/memory-autoload/.codex-plugin/plugin.json`.
- OpenCode: `SKILL.md` discovery is compatible with agent skills, but this
  session-start hook plugin is not packaged for OpenCode.
- Antigravity CLI: uses a separate root `plugin.json` layout, which is not
  included in this plugin.
- Windows: hooks must run through Git Bash (Claude Code on Windows ships its own).
  The scripts embed an MSYS PATH guard so Git for Windows' `usr/bin` tools take
  precedence over the native `find.exe`/`tar.exe`.
