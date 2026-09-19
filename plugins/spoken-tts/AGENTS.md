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

`SPOKEN_SYNC=1` runs speak inline (tests). `SPOKEN_NATIVE_PROVIDER` overrides
OS native detection (`say` / empty).
