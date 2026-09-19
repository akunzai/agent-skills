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
`--yes` for non-interactive setup.

The root `scripts/upgrade.sh` and `scripts/uninstall.sh` use the same interactive
runtime/plugin-state flow. Upgrade refreshes the local integration; uninstall
removes it after the selected plugin-manager entry is removed.
Plugin-local `configure-host.sh`, `remove-host.sh`, and `remove-grok.sh` are
internal helpers and are not public lifecycle entry points. `remove-grok.sh`
drops leftover Grok hook files and the CodexBar grok rule without uninstalling
the plugin from other runtimes.

## Checks

From the repository root:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
mise run lint
```

The two marketplace manifests (`.claude-plugin/`, `.agents/plugins/`) must
continue to resolve to this shared plugin root; Copilot and Cursor reuse the
Claude one, so there is no third. Grok Build is not a supported plugin
runtime: do not add `.grok-plugin/`. Configure removes leftover
`~/.grok/hooks/codexbar-quota-handoff.json` files from older installs so they
cannot claim the Claude flag.

The reminder's host detection depends on each runtime's hook identity variables
and the order they are tested in (`../../docs/agents/harnesses.md`). Reminder
env cases: `CURSOR_INVOKED_AS=cursor-agent` must select
`quota-low-cursor.json`, not `quota-low-claude.json`.

## Prevent Recurrence

- Propose a candidate only when you can name who hits it again, where, and on
  what change.
- On confirmation, offer the first tier that reaches them and only that one:
  enforce it (assert/type/test) with its size quoted, else a comment at that
  site, else the nearest existing topic document with a backtick-path pointer here
  and one sentence on why the tiers above cannot hold it.
- When adding to a file, audit the rest of it in the same pass; drop entries
  once tests or current documentation make them redundant.
