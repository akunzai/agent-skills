# spoken Development

## Local setup

From the repository root:

```bash
bash scripts/setup.sh --plugin spoken-tts
```

Pass `--local` to register this checkout. There is no plugin-local
setup/upgrade/uninstall script.

## Checks

```bash
bash tests/spoken-manifest.sh
bash tests/spoken-cli.sh
bash tests/plugin-version-bump.sh
mise run lint
```

CLI `speak`/`test` wait until playback finishes. `SPOKEN_SYNC=1` runs speak
inline for hooks (tests). `SPOKEN_NATIVE_PROVIDER` overrides OS native
detection (`say` / empty).

## Hooks: two files, two formats

`hooks.json` (plugin root) — **agy format**: flat handler lists under each
event name (`Stop: [{ type, command, timeout }]`). Do not add a nested
`{ "hooks": [...] }` wrapper here; agy ignores it.

`hooks/hooks.json` — **Copilot/Claude Code format**: nested wrapper
(`Stop: [{ hooks: [{ command }] }]`). Keep as-is for Copilot compatibility.

When editing either file, leave the other unchanged.
