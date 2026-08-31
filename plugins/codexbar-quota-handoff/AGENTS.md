# codexbar-quota-handoff Development

## Local setup

From the repository root, run the only public setup entry point:

```bash
bash scripts/setup.sh --plugin codexbar-quota-handoff --threshold 0.9
```

In a terminal the script interactively installs the plugin into a selected
Claude Code, Codex, or Copilot runtime, then configures the host integration.
It detects and skips an existing plugin install. Pass `--local` to register
this checkout instead of the published GitHub source, or use `--runtime` and
`--yes` for non-interactive setup. Grok uses only the global hook.

The root `scripts/upgrade.sh` and `scripts/uninstall.sh` use the same interactive
runtime/plugin-state flow. Upgrade refreshes the local integration; uninstall
removes it after the selected plugin-manager entry is removed.
Plugin-local `configure-host.sh` and `remove-host.sh` are internal post-action
helpers and are not public lifecycle entry points.

## Checks

From the repository root:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
mise run lint
```

The three marketplace manifests must continue to resolve to this shared plugin
root. Grok's reminder path is the Stop-only global hook
`~/.grok/hooks/codexbar-quota-handoff.json` written by the root setup (plugin
marketplace hooks are not registered by Grok Build 1.0.x).

Copilot needs no fourth manifest: it reads `.claude-plugin/marketplace.json`
and `.claude-plugin/plugin.json`, and registers the bundled `hooks/hooks.json`
in its Claude-shaped nested form. See @../../docs/agents/copilot-cli.md for the
host-detection order the reminder depends on.

## Self-Reflection

- Propose concise, non-obvious candidates before recording them.
- On confirmation, store them in the nearest existing topic document and add
  an `@path` pointer here; prune facts once tests or current documentation make
  them redundant.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md`
directly.
