---
name: aube
description: >-
  Use when managing a Node.js project's dependencies or scripts with aube
  (https://aube.jdx.dev/), or migrating a project from pnpm, npm, or bun to
  aube — including its lockfile, CI, lifecycle-script jail, and Dependabot
  handling.
---

# aube

Use aube as the Node.js package manager, installed and pinned through mise. aube
is jdx's fast, security-first package manager (https://aube.jdx.dev/); this skill
captures the *how we use it here* decisions, not the official reference.

## Quick start

Install and pin aube via mise (not standalone). Daily work goes through
`aubr <script>` (= `aube run`); CI uses `aube ci` (frozen lockfile). Keep a
Dependabot-compatible lockfile, keep one version source in `mise.toml`, and
accept aube's strict supply-chain defaults.

## Core conventions

1. **Install through mise** — `mise use aube` and pin in `[tools]` (e.g.
   `aube = "1.25.1"`); never install aube standalone. See
   [`mise`](../mise/SKILL.md).
2. **Single version source** — `mise.toml` drives both node and aube; after
   migrating, remove the `packageManager` field from `package.json` so versions
   do not fork.
3. **Keep a Dependabot-compatible lockfile** — aube reads and writes an existing
   `pnpm-lock.yaml` or `package-lock.json` in place, so keep that committed
   rather than switching to `aube-lock.yaml`. Dependabot has no aube ecosystem
   and cannot maintain `aube-lock.yaml`; staying on a compatible lockfile lets
   Dependabot keep bumping dependencies. Adopt `aube-lock.yaml` only when you do
   not rely on Dependabot.
4. **Accept supply-chain defaults** — aube denies lifecycle scripts by default,
   holds new releases behind a 24h cooling window, checks typosquats, and
   downgrades trust. Keep these; allow only the specific builds you need.
5. **Phased migration** — pilot in one project or subcomponent before
   committing; do not replace wholesale.

## Commands

| Command | Use |
| --- | --- |
| `aubr <script>` (= `aube run`) | Daily driver: `aubr build`, `aubr test`, `aubr dev`, `aubr preview`. On PATH via mise. |
| `aube ci` | Frozen-lockfile install for CI (replaces `pnpm install --frozen-lockfile`); runs no scripts by default. |
| `aube install` | Local setup / Docker layers. |
| `aube add <pkg>` | Add a dependency (malware-checked by default). |
| `aubx <tool>` (= `aube dlx`) | Run a one-off tool without installing. |
| `aube exec [--] <cmd>` | Run a binary from deps; bypasses third-party tooling that auto-detects the package manager. Put `--` before the binary so aube does not swallow its flags (see Gotchas). |

## CI (GitHub Actions)

Replace `pnpm/action-setup` + `actions/setup-node` with `jdx/mise-action@v4`,
then install and test through aube. mise-action's `cache: true` caches only the
mise-installed tool *binaries* (aube/node), **not** aube's package store — without
an explicit store cache every `aube ci` re-downloads all packages. Add an
`actions/cache` step keyed on the lockfile, with the path from `aube store path`
(it carries a `vN` suffix, e.g. `~/.local/share/aube/store/v1`):

```yaml
- uses: jdx/mise-action@v4
  with:
    install_args: aube node   # install only these tools; versions come from mise.toml
    cache: true               # caches the tool binaries, not the aube store
- name: Cache aube store
  uses: actions/cache@v6
  with:
    path: ~/.local/share/aube/store   # from `aube store path`
    key: ${{ runner.os }}-aube-store-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: ${{ runner.os }}-aube-store-
- run: aube ci
- run: aubr test
```

## Lifecycle scripts

aube jails lifecycle (build) scripts by default. Allow only the packages that
genuinely need them via the `pnpm.allowBuilds` config (read from the
pnpm-style config / lockfile), e.g. `esbuild`, `workerd`, `miniflare`. Verify
locally (`aube ci` plus the test suite) before relying on CI.

## Gotchas

- **Third-party actions auto-detect the package manager** — e.g.
  `wrangler-action` sees `pnpm-lock.yaml` and picks pnpm, which is no longer
  installed, so the build breaks. Drop the action and call the binary directly:
  `aube exec wrangler deploy` with `CLOUDFLARE_API_TOKEN` in env.
- **`aube exec` swallows global flags** — `aube exec tsc --version` prints aube's
  own version because aube intercepts `--version`/`-v`/`-r`/`-F` before the binary
  sees them. Put `--` before the binary so its flags pass through:
  `aube exec -- tsc --version`, `aube -F <name> exec -- wrangler --version`.
- **Lifecycle-script jail** — the first `aube ci` will not run build scripts
  (esbuild/workerd/…) until allowed via `pnpm.allowBuilds`; test locally first.
- **Dependabot has no aube ecosystem** — it cannot read or update
  `aube-lock.yaml`. Keep a compatible lockfile (`pnpm-lock.yaml` /
  `package-lock.json`, which aube reads and writes in place) and the matching
  `npm` ecosystem in `dependabot.yml`, so Dependabot keeps maintaining the
  lockfile. Switch to `aube-lock.yaml` only if you accept that Dependabot will
  stop updating it. Re-check this if aube support lands later — the authoritative
  list is GitHub's [supported ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories).
- **bun -> aube is also a runtime migration** — dropping bun means migrating the
  runtime (`node:child_process`, etc.) and the test framework (bun test ->
  Vitest); scope that separately from the package-manager switch.
- **starship `nodejs`/`package` modules loop under aube** — starship's
  default-enabled `nodejs` and `package` modules probe Node / the package manager
  on every prompt; with aube active this can spiral into a `command not found`
  loop that makes the shell impossible to type into. Set `disabled = true` under
  both `[nodejs]` and `[package]` in `~/.config/starship.toml`.

## Related

- [`mise`](../mise/SKILL.md) — installs and pins aube; provides the single
  version source and the CI action.
