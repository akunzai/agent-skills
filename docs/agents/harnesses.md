# Harness behaviour

What this repository's skills and plugins rely on under each runtime, one
section per harness. Plugin-specific consequences live in that plugin's
`AGENTS.md`; this file holds the runtime behaviour behind them.

## Claude Code

- **Update key**: marketplace plugins are pinned on the `version` string in
  that plugin's `.claude-plugin/plugin.json`.
  [`claude plugin update`](https://code.claude.com/docs/en/plugins-reference#version-management)
  skips when that string is unchanged, even if the git SHA moved. Root
  `.claude-plugin/plugin.json` is the `skills add` catalog, not a plugin.
- **Manual-only skills**: `disable-model-invocation: true` in `SKILL.md`
  frontmatter is honoured directly.
- **Plugin subagents** cannot nest, and do not support `hooks` or
  `permissionMode`. A `permissionMode` field on a plugin agent is ignored and
  logs `[WARN] ... sets permissionMode, which is ignored for plugin agents` to
  the debug log, once per file.

## Codex CLI

- **Marketplace**: plugins resolve only from `.agents/plugins/marketplace.json`,
  so every plugin needs an entry there.
- **Agents**: there is no plugin-bundled agent mechanism. Subagents are copies
  in a personal (`~/.codex/agents/`) or trusted-project (`.codex/agents/`)
  agents directory; the plugin `version` does not update them, so run root
  `scripts/upgrade.sh` after a release. Subagents may nest one hop.
- **Manual-only skills**: `disable-model-invocation` is not yet honoured
  ([openai/codex#29989](https://github.com/openai/codex/issues/29989)). Add
  `agents/openai.yaml` beside `SKILL.md` with
  `policy.allow_implicit_invocation: false`; its
  `interface.display_name`/`short_description` feed Codex's skill picker.
- **Dispatch gotchas**:
  - A prompt that both names an `agent_type` and asks the orchestrator to fully
    inherit conversation history is rejected by Codex's collaboration layer.
    Dispatch without full history inheritance (e.g. `fork_turns: none`).
  - The root session relays whatever the subagent's final message claims
    (counts, exit codes) without independently checking raw output. Ask
    explicitly for the subagent's raw output when the claim matters.

## GitHub Copilot CLI

Verified against Copilot CLI 1.0.82 on macOS.

### Manifests

Copilot's plugin loader accepts `.claude-plugin/marketplace.json` and
each plugin's `.claude-plugin/plugin.json` as-is, so no Copilot-specific
manifest exists in this repository. Copilot uses that plugin `version` as
its update key.

```bash
copilot plugin marketplace add akunzai/agent-skills   # or a local checkout path
copilot plugin install <plugin>@akunzai-agent-skills
```

GitHub's own docs describe `plugin.json` at the plugin root and
`marketplace.json` under `.github/plugin/`, with `.claude-plugin/` documented
only for the marketplace file. The plugin-manifest path is compatibility
behaviour rather than a documented contract — if a Copilot release stops
resolving `.claude-plugin/plugin.json`, add `.copilot-plugin/` rather than
moving the file.

### What Copilot picks up from a plugin

- `agents/*.md` — Claude-format subagent definitions load unchanged and are
  addressed by the same `<plugin>:<role>` name Claude Code uses. The
  `tools:` frontmatter maps onto Copilot's own tool names (`Read, Grep, Glob`
  resolves to `view, grep, glob`, with no `bash` and no edit tools), so a
  read-only role stays read-only.
- `hooks/hooks.json` — the Claude-shaped nested form
  (`hooks.<Event>[].hooks[].command`) registers, `${CLAUDE_PLUGIN_ROOT}` is
  substituted, and PascalCase `Stop` / `PostToolUse` are accepted alongside
  Copilot's own camelCase event names. A hook exiting 2 surfaces its stderr to
  the user and the session continues.
- `skills/*/SKILL.md` — plugin skills load, as do personal skills from
  `~/.agents/skills/` and a project's `.claude/skills/`.

### Skills and slash commands

Copilot registers every loaded, user-invocable skill as a slash command
(`copilot skill list` shows what is loaded). It has no built-in wrap-up
command; `codexbar-quota-handoff` injects its wrap-up procedure through the
Stop / PostToolUse hook instead.

There is no per-skill invocation control as of this writing — only a global
`/skills` enable/disable — so Copilot still auto-invokes a manual-only skill.

### Hook identity

`COPILOT_CLI=1` (with `COPILOT_PROJECT_DIR`) identifies a Copilot hook run.
Copilot also exports a bare `PLUGIN_ROOT` to plugin hooks and substitutes both
`${CLAUDE_PLUGIN_ROOT}` and `${PLUGIN_ROOT}`. `PLUGIN_ROOT` is therefore *not*
Codex-specific: any shared hook must test `COPILOT_CLI` before it, or Copilot
is misreported as Codex.

## Cursor CLI

The binary is `cursor-agent`. Verified against Cursor CLI 2026.09.10 on 2026-09-15.

### Install through Claude Code

Cursor CLI loads every Claude Code plugin enabled in `~/.claude/settings.json`
from `~/.claude/plugins/cache`: its skills, `agents/*.md`, and hooks. Nothing
is installed on the Cursor side. An isolated-`HOME` probe with only that
settings file and plugin directory listed the `cheap-dev-workers` roles and
ran the cached `quota-reminder.sh`; the same probe without them listed neither.
`cursor-agent` hardcodes third-party config loading on; the IDE toggle does not
apply to the CLI
([forum](https://forum.cursor.com/t/no-way-to-opt-out-of-third-party-claude-code-codex-config-loading-the-flag-is-hardcoded/166558)).
Cursor's [third-party hooks doc](https://cursor.com/docs/reference/third-party-hooks)
covers only settings-file hooks, so this rests on observed behaviour.

So the lifecycle scripts have no Cursor runtime: install with Claude Code, and
update with `claude plugin update`. Cursor sees whatever version that cache
holds. Do not add a Cursor runtime to `scripts/manage-plugins.sh`.

Without Claude Code, Cursor CLI indexes this repo's `.claude-plugin/`
marketplace directly; enable plugins in-session with `/plugin` or IDE
Customize. There is no plugin install CLI. The source takes `github.com/owner/repo`
(scheme optional); a bare `owner/repo` fails with `Invalid URL format`.

```bash
cursor-agent plugin marketplace add github.com/akunzai/agent-skills
```

Enabling a plugin there as well as in Claude Code runs its hooks twice, because
Cursor runs every matching hook from every source.

Name `cursor-agent` only: `~/.local/bin/agent` can be the same Cursor inode,
and Grok also ships `~/.grok/bin/agent`. `--plugin-dir` loads a local Claude
plugin's skills and `agents/*.md` by name.

### Plugin agents

Plugin `agents/*.md` load with `tools:` and `model` stripped. The only
permission field Cursor reads on a plugin agent is `permissionMode: readonly`;
the documented `readonly: true` does nothing there. Workspace `.cursor/agents`
and `.claude/agents` files do honour `readonly: true`, and `model:
composer-2.5-fast` pinned there.

Readonly runs the subagent in Ask mode: Read, Grep, and Glob work; Write and
every shell call, `ls` included, fail with `You are in ask mode and cannot run
non read-only tools`. Probed with neutral agents that differed only in that
field, checking the files on disk rather than the agent's report. Both
`permissionMode` readings (Cursor enforcing it, Claude Code ignoring it) are
observed, not documented: re-probe when Cursor documents plugin agents or
Claude Code starts rejecting the field.

The CLI discovers custom agents only in the workspace `.cursor/agents` and
`.claude/agents`, plus enabled plugins. The user-level `~/.cursor/agents`,
`~/.claude/agents`, and any `.codex/agents` that
[Cursor's subagent docs](https://cursor.com/docs/subagents) list did not load,
so a per-user Cursor projection of the roles is not an option.

### Task

The Task tool has optional `model` and no `effort` field. Default inherit
unless the user explicitly requests a model. The dispatch allowlist is a short
subset: `composer-2.5-fast` accepted; `cursor-grok-4.6-low` rejected. Plugin
frontmatter `model` did not stick when Task passed inherit.

### Hooks

Claude nested `PostToolUse` runs for this repo's `hooks.json`, in print mode
too. `Stop` did not fire on CLI print/ask/no-tool turns.

Exit 2 on `postToolUse` did not inject stderr into the model and did not block
later tools. `additional_context` plus exit 0 reached the model, but the model
relayed it in only one of two live probes.

Identity is `CURSOR_INVOKED_AS=cursor-agent`. `CURSOR_PLUGIN_ROOT` leaks across
plugins on `postToolUse` — do not use it as identity.

A cached `codexbar-quota-handoff` older than 1.2.1 has no `CURSOR_INVOKED_AS`
check, so under Cursor it claims `quota-low-claude.json`. Before a live hook
probe, point `XDG_STATE_HOME` at a scratch directory, and account for the
Claude Code cached copy running alongside any `--plugin-dir` copy.
