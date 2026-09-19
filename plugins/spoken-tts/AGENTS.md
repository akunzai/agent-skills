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

## Prevent Recurrence

- Propose a candidate only when you can name who hits it again, where, and on
  what change.
- On confirmation, offer the first tier that reaches them and only that one:
  enforce it (assert/type/test) with its size quoted, else a comment at that
  site, else the nearest existing topic document with a backtick-path pointer here
  and one sentence on why the tiers above cannot hold it.
- When adding to a file, audit the rest of it in the same pass; drop entries
  once tests or current documentation make them redundant.
