---
name: aube
description: >-
  Use when managing a Node.js project's dependencies or scripts with aube
  (https://aube.sh/), or migrating a project from pnpm, npm, or bun to
  aube — including its lockfile, CI, lifecycle-script jail, and Dependabot
  handling.
---

# aube

Use aube as the Node.js package manager, installed and pinned through mise. aube
is jdx's fast, security-first package manager (https://aube.sh/); this skill
captures the *how we use it here* decisions, not the official reference.

## Quick start

Install and pin aube via mise (not standalone). Daily work goes through
`aubr <script>` (= `aube run`); CI uses `aube ci` (frozen lockfile). Keep a
Dependabot-compatible lockfile, keep one version source in `mise.toml`, and
accept aube's strict supply-chain defaults.

## Core conventions

1. **Install through mise** — `mise use aube` and pin in `[tools]` (e.g.
   `aube = "2.2.9"`); never install aube standalone. See
   [`mise`](../mise/SKILL.md).
2. **Single version source** — `mise.toml` drives both node and aube; after
   migrating, remove the `packageManager` field from `package.json` so versions
   do not fork.
3. **Keep a Dependabot-compatible lockfile** — aube reads and writes an existing
   `pnpm-lock.yaml` or `package-lock.json` in place, so keep that committed
   rather than switching to `aube-lock.yaml`. Dependabot lacks an aube ecosystem
   and cannot maintain `aube-lock.yaml`. For new projects, set
   `defaultLockfileFormat = "pnpm"` in `aube-workspace.yaml`, `.npmrc`, or
   `settings.toml`. Adopt `aube-lock.yaml` only without Dependabot. Locked
   versions are trusted on frozen installs (`aube ci`) without per-install
   revalidation.
4. **Accept supply-chain defaults** — aube denies lifecycle scripts by default,
   holds new releases behind a 24h cooling window, checks typosquats, and
   downgrades trust. Keep these; allow only the specific builds you need.
5. **Phased migration** — pilot in one project or subcomponent before
   committing; do not replace wholesale.

## Commands

| Command | Use |
| --- | --- |
| `aubr <script>` (= `aube run`) | Daily driver: `aubr build`, `aubr test`, `aubr dev`. Echoes `$ <cmd>` to stderr (`--silent` to mute). |
| `aube test` | Auto-installs on stale state, then runs `test` script. |
| `aube ci` | Frozen-lockfile install for CI; runs no scripts by default. |
| `aube install` | Local setup / Docker layers. |
| `aube add <pkg>` | Add a dependency (malware-checked by default). |
| `aubx <tool>` (= `aube dlx`) | Run a one-off tool without installing. |
| `aube exec [--] <cmd>` | Run binary from deps. Put `--` before binary so flags pass through (see Gotchas). |
| `aube approve-builds` | Interactive review/approval of lifecycle build scripts. |

## CI (GitHub Actions)

Prefer `jdx/aube-action@v1` over `jdx/mise-action@v4` for installing aube.
mise's aqua backend verifies GitHub artifact attestations against aube's repo
identity, and aube's repo has moved (`jdx/aube` -> `aubepkg/aube`); the aqua
registry entry lags behind, so attestation verification currently fails for
every aube release from 2.2.8 onward, breaking `mise install aube` entirely.
`jdx/aube-action@v1` downloads the release binary directly (no attestation
check) and sidesteps this. It also installs Node.js in the same step via
`node-version: auto`, which resolves the version from `mise.toml`,
`.tool-versions`, `.nvmrc`, `.node-version`, or `package.json`
`devEngines.runtime` — no separate `actions/setup-node` needed:

```yaml
- uses: jdx/aube-action@v1
  with:
    node-version: auto   # or an explicit version; omit to skip installing node
```

If `mise-action` is still used for other tools in the same job, disable
attestation checks for aube specifically with
`MISE_AQUA_GITHUB_ATTESTATIONS: false` in that step's `env`, and revisit once
the aqua registry catches up.

Neither action caches aube's own directories. Per aube's CI guide (Cache
choices: https://aube.sh/package-manager/ci.html#cache-choices), the content
store and registry metadata live in **separate** directories — resolve both
dynamically rather than hardcoding paths, since they depend on config:

```yaml
- name: Get aube store and cache paths
  id: aube-paths
  run: |
    echo "store-path=$(aube store path)" >> "$GITHUB_OUTPUT"
    echo "cache-path=$(aube cache path)" >> "$GITHUB_OUTPUT"
- name: Cache aube store
  uses: actions/cache@v6
  with:
    path: ${{ steps.aube-paths.outputs.store-path }}   # content store, default ~/.local/share/aube/store/v1
    key: ${{ runner.os }}-aube-store-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: ${{ runner.os }}-aube-store-
- name: Cache aube registry metadata
  uses: actions/cache@v6
  with:
    path: ${{ steps.aube-paths.outputs.cache-path }}   # registry metadata, default ~/.cache/aube
    key: ${{ runner.os }}-aube-cache-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: ${{ runner.os }}-aube-cache-
- run: aube ci
- run: aubr test
```

## Lifecycle scripts

aube jails lifecycle scripts by default. Allow needed builds via
`aube approve-builds` or `allowBuilds` in `aube-workspace.yaml` /
`pnpm.allowBuilds` in `package.json`, e.g. `esbuild`, `workerd`. Verify
locally before relying on CI. Jailed builds can also be granted explicit
permissions (`jailBuildPermissions`).

## Gotchas

- **Third-party actions auto-detect the package manager** — e.g.
  `wrangler-action` picks missing pnpm on `pnpm-lock.yaml`. Call binary
  directly: `aube exec wrangler deploy` with `CLOUDFLARE_API_TOKEN` in env.
- **`aube exec` swallows global flags** — `aube exec tsc --version` prints aube's
  version. Put `--` before binary: `aube exec -- tsc --version`.
- **Lifecycle-script jail** — first `aube ci` skips unapproved build scripts
  until allowed via `aube approve-builds` or `allowBuilds`; test locally first.
- **`aubr` echoes commands to stderr** — prints expanded command prefixed with `$`
  to stderr (matching npm/pnpm); pass `--silent` / `-s` if scripts parse stderr.
- **Global installs use aube data root in 2.x** — `aube add -g` installs to
  `$XDG_DATA_HOME/aube/bin` (`~/.local/share/aube/bin`), ignoring `PNPM_HOME`.
  Add this directory to `$PATH`.
- **Dependabot has no aube ecosystem** — cannot read `aube-lock.yaml`. Keep
  `pnpm-lock.yaml` (or set `defaultLockfileFormat = "pnpm"`) with `npm` in
  `dependabot.yml`. Switch to `aube-lock.yaml` only if abandoning Dependabot.
- **bun -> aube is also a runtime migration** — migrating runtime (`node:*`)
  and test runner (bun test -> Vitest) is separate from package-manager switch.
- **starship `nodejs`/`package` modules loop under aube** — disable in
  `~/.config/starship.toml` (`[nodejs]` and `[package]` `disabled = true`) to
  prevent prompt loops.
- **`mise install aube` fails GitHub attestation verification** — aube's repo
  moved `jdx/aube` -> `aubepkg/aube`; the aqua registry's expected attestation
  identity hasn't caught up. Use `jdx/aube-action@v1` in CI instead (see CI
  section) rather than disabling attestation checks globally.

## Related

- [`mise`](../mise/SKILL.md) — installs and pins aube; provides the single
  version source and the CI action.
