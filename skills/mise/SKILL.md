---
name: mise
description: >-
  Use when setting up or managing a project's toolchain, language runtimes, or
  task running with mise (https://mise.jdx.dev/), when migrating a Makefile or
  npm scripts to mise tasks, or when wiring mise into CI or container builds.
---

# mise

Manage a project's dev tools, language runtimes, and tasks through a single
committed `mise.toml`. The official docs at https://mise.jdx.dev/ cover the full
surface; this skill captures the *how we use it here* decisions, not the
reference.

## Quick start

One `mise.toml` per repo is the single source of truth for every tool, runtime,
and task. Pin versions explicitly, prefer built-in backends (`aqua`, `github`),
drive work through `mise run <task>`, and adopt in phases: host -> CI ->
containers.

## Core conventions

1. **Single source of truth** — one `mise.toml` at the repo root declares all
   tools, runtimes, and tasks. Do not split version declarations between
   `mise.toml` and `package.json` `packageManager`/corepack; remove the
   duplicate once migrated.
2. **Pin explicitly** — choose each tool's version deliberately for
   reproducibility: a major or channel for runtimes (`python = "3.14"`,
   `java = "temurin-25"`, `node = "lts"`, which float the patch within a fixed
   line), and `latest` for low-risk, fast-moving tools — especially linters
   (`shellcheck = "latest"`, `actionlint = "latest"`, `uv = "latest"`), which
   benefit from always running the newest rules.
3. **Tasks over Makefile/npm scripts** — define `[tasks]` with `run`,
   `description`, and `depends` chains; run via `mise run <task>`. mise
   orchestrates multi-tool workflows, not just Node.
4. **Built-in backends** — prefer `aqua:` and `github:` (built in,
   provenance-verified). Avoid the deprecated `ubi:` backend and external
   fetchers; migrate `ubi:owner/repo` -> `github:owner/repo` (same syntax).
5. **Idiomatic version files** — enable only when you need interop with existing
   `.nvmrc` / `.node-version` / `package.json` `devEngines.runtime`:
   `mise settings add idiomatic_version_file_enable_tools node`.
6. **Phased adoption** — host first, then CI, then containers; keep the old path
   working until each phase is verified.

## mise.toml patterns

```toml
[tools]
shellcheck = "latest"   # linter: latest for the newest rules
actionlint = "latest"   # linter: latest for the newest rules
uv = "latest"           # low-risk, fast-moving
node = "lts"            # runtime: LTS channel, floats the patch
java = "temurin-25"     # runtime: Temurin major, floats the patch
python = "3.14"         # runtime: pin the minor line

[tasks.test]
description = "Run all test scripts"
run = "..."

[tasks.lint]
description = "Run all linters"
depends = ["lint-shell", "lint-actions"]
```

Translate a Makefile or npm script target to a task verbatim — preserve shell
semantics (pipes, loops, `$()`), keep the existing names, and add `depends` to
model the ordering the old target relied on.

## CI (GitHub Actions)

Use `jdx/mise-action@v4`; it reads the committed `mise.toml` and installs and
caches the pinned tools, replacing per-tool setup actions
(`actions/setup-python`, `astral-sh/setup-uv`, `raven-actions/actionlint`, …).
Run the actual work through tasks:

```yaml
- uses: jdx/mise-action@v4
- run: mise run test
- run: mise run lint
```

Scope a job to only the tools it needs with `install_args` — `with: { install_args:
"node aube" }` installs just those (versions still come solely from `mise.toml`), so
a JS job does not drag in unrelated toolchains like the dotnet SDK. The built-in
`cache: true` (on by default) caches the installed tool binaries.

## Containers

- Pin the mise binary by version and verify its sha256; do not pipe
  `curl | bash` in production images.
- Pre-cache tools system-wide with `mise install --system` (lands in
  `/usr/local/share/mise`) so a dropped-privilege runtime user (e.g. uid 1000)
  can find them; ensure the result is world-readable.

## Gotchas

- **Untrusted `mise.toml`** — mise refuses to load a config it has not been
  trusted to run; on a fresh checkout `mise install` and tasks silently no-op
  until you run `mise trust` once in the repo. `jdx/mise-action` trusts the
  config automatically, so this is a host-only first-run step.
- **Version-source fragmentation** — keeping `packageManager`/corepack alongside
  `mise.toml` creates two version sources that drift. Consolidate to `mise.toml`.
- **`ubi:` deprecation** — it still works but warns; switch to the built-in
  `github:` backend (same `owner/repo` syntax, with provenance verification).
- **Container tool visibility** — tools installed into root's home are invisible
  to a uid-dropped runtime user; use `mise install --system` instead.
- **macOS Gatekeeper quarantine** — precompiled binaries mise downloads on macOS
  (e.g. PHP) can be quarantined and refuse to run. On a Gatekeeper warning, clear
  the attribute on the installed path:
  `xattr -d com.apple.quarantine ~/.local/share/mise/installs/<tool>/<version>/...`.

## Related

- [`aube`](../aube/SKILL.md) — the Node.js package manager installed and pinned
  through mise.
