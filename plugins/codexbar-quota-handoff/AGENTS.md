# codexbar-quota-handoff Development

## Local setup

Run the host integration from the repository checkout:

```bash
bash scripts/setup.sh --threshold 0.9
```

The script prints Claude Code and Codex marketplace commands using the
checkout's absolute path (Grok uses only the global hook). Run the relevant
commands to test unpublished changes; it does not invoke plugin managers
automatically.

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

## Self-Reflection

- Propose concise, non-obvious candidates before recording them.
- On confirmation, store them in the nearest existing topic document and add
  an `@path` pointer here; prune facts once tests or current documentation make
  them redundant.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md`
directly.
