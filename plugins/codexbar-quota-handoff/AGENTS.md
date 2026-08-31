# codexbar-quota-handoff Development

## Local setup

Run the host integration from the repository checkout:

```bash
bash scripts/setup.sh --threshold 0.9
```

By default the script prints Claude Code, Codex, and Copilot marketplace
commands for the published GitHub source `akunzai/agent-skills` (so plugin
managers can track remote updates). Pass `--local` to print this checkout's
absolute path instead when testing unpublished changes. Grok uses only the
global hook. Setup does not invoke plugin managers automatically.

## Checks

From the repository root:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
mise run lint
```

The three marketplace manifests must continue to resolve to this shared plugin
root. Grok's reminder path is the Stop-only global hook
`~/.grok/hooks/codexbar-quota-handoff.json` written by `setup.sh` (plugin
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
