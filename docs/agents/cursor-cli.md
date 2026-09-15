# Cursor CLI plugin loading

What this repository's plugins rely on under Cursor CLI (`cursor-agent`).
Verified against Cursor CLI 2026.09.10 on 2026-09-15.

## Install through Claude Code

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
holds.

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

## Plugin agents

Plugin `agents/*.md` load with `tools:` and `model` stripped. The only
permission field Cursor reads on a plugin agent is `permissionMode: readonly`;
the documented `readonly: true` does nothing there. Workspace `.cursor/agents`
and `.claude/agents` files do honour `readonly: true`, and `model:
composer-2.5-fast` pinned there.

Readonly runs the subagent in Ask mode: Read, Grep, and Glob work; Write and
every shell call, `ls` included, fail with `You are in ask mode and cannot run
non read-only tools`. Probed with neutral agents that differed only in that
field, checking the files on disk rather than the agent's report.

So `render-roles.awk` emits `permissionMode: readonly` for `read-only` roles
(`repo-explorer`, `commit-writer`, `log-summarizer`), and skills dispatch those
on Cursor CLI. `check-runner` needs shell, so it gets no such field; with
`tools:` ignored it would hold Write and Edit, so its work stays in primary.
Claude Code ignores `permissionMode` on plugin agents and logs `[WARN] ... sets
permissionMode, which is ignored for plugin agents` to its debug log; Copilot
CLI loads the agents unchanged.

The CLI discovers custom agents only in the workspace `.cursor/agents` and
`.claude/agents`, plus enabled plugins. The user-level `~/.cursor/agents`,
`~/.claude/agents`, and any `.codex/agents` that
[Cursor's subagent docs](https://cursor.com/docs/subagents) list did not load,
so a per-user Cursor projection of the roles is not an option.

## Task

The Task tool has optional `model` and no `effort` field. Default inherit
unless the user explicitly requests a model. The dispatch allowlist is a short
subset: `composer-2.5-fast` accepted; `cursor-grok-4.6-low` rejected. Plugin
frontmatter `model` did not stick when Task passed inherit.

## Hooks

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

## Reviewer checks

- Do not add a Cursor runtime to `scripts/manage-plugins.sh`; Cursor inherits
  the Claude Code install.
- Reminder env cases: `CURSOR_INVOKED_AS=cursor-agent` must select
  `quota-low-cursor.json`, not `quota-low-claude.json`. Do not key identity on
  `CURSOR_PLUGIN_ROOT`.
- Plugin read-only roles carry `permissionMode: readonly`, never
  `readonly: true`, and `check-runner` carries neither;
  `tests/cheap-dev-workers-agents-content.sh` enforces both.
- Skills keep `check-runner` work in primary on Cursor CLI and may dispatch the
  read-only roles.
- Both `permissionMode` readings are observed, not documented: re-probe when
  Cursor documents plugin agents or Claude Code starts rejecting the field.
