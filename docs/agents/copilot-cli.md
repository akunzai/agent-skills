# GitHub Copilot CLI compatibility

What this repository's plugins rely on when they run under GitHub Copilot CLI.
Verified against Copilot CLI 1.0.82 on macOS.

## Copilot reuses the Claude manifests

Copilot's plugin loader accepts `.claude-plugin/marketplace.json` and
`.claude-plugin/plugin.json` as-is, so no Copilot-specific manifest exists in
this repository:

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

## What Copilot picks up from a plugin

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

## Detecting Copilot from a shared hook

`COPILOT_CLI=1` (with `COPILOT_PROJECT_DIR`) identifies a Copilot hook run.

- [copilot-cli] Copilot also exports a bare `PLUGIN_ROOT` to plugin hooks and
  substitutes both `${CLAUDE_PLUGIN_ROOT}` and `${PLUGIN_ROOT}`. `PLUGIN_ROOT`
  is therefore *not* Codex-specific: any shared hook must test `COPILOT_CLI`
  before it, or Copilot is misreported as Codex.

## Slash commands

Copilot has no built-in `/handoff`. It does register every loaded, user-
invocable skill as a slash command, so `/handoff` resolves through this
repository's `handoff` skill. `copilot skill list` shows what is loaded.
