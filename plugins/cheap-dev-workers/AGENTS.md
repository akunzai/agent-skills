# cheap-dev-workers Development

## Local setup

How each runtime loads these roles is in `../../docs/agents/harnesses.md`.
Claude Code and GitHub Copilot CLI read `agents/` straight from the installed
plugin, so no runtime-specific copy of the role definitions exists; Cursor CLI
reads the Claude Code install, so there is no Cursor runtime to select. Codex
CLI needs copies. From the repository root:

```bash
bash scripts/setup.sh --plugin cheap-dev-workers
```

Select the runtime in the interactive installer; scripts and CI may use
`--runtime copilot --yes`. Selecting Copilot leaves Codex agents untouched.
Selecting Codex copies `codex-agents/*.toml` into `~/.codex/agents/` (personal
scope only — this plugin does not install into a project's `.codex/agents/`).

## Worker Role sources

`roles/` is the authority. `agents/*.md` and `codex-agents/*.toml` are
projections of it and must never be hand-edited: the runtimes and the
installers read those fixed paths, so they stay committed, but
`scripts/render-roles.sh --check` fails the moment they stop matching
`roles/`.

```bash
plugins/cheap-dev-workers/scripts/render-roles.sh --check   # read-only
mise run render-roles                                       # regenerate
```

The artifacts carry no generated-by header, deliberately: adding one would
change the prompt bytes that reach the model. Ownership is marked out of band
instead — by this section, by `linguist-generated=true` in `.gitattributes`,
and by the failing check.

`roles/shared.role` holds semantics, not bytes. It declares each invariant's
id, which roles carry it, and a `class`:

- `shared` — same meaning in both runtimes; the wording still differs, which is
  unfinished normalization rather than design
- `runtime` — deliberately different because the runtimes differ (e.g. nesting
  depth; see `../../docs/agents/harnesses.md`)
- `drift` — differs with no runtime justification

Per-role, per-runtime prose lives in `roles/<role>.role`, because the same
invariant is worded differently in all four roles today. The grammar has no
quoting, escaping, or continuation: anything it cannot hold verbatim is
rejected with a `file:line` error rather than silently transformed.

### What the checks do and do not prove

`--check` proves the eight artifacts are exactly what `roles/` projects, and
`tests/cheap-dev-workers-agents-content.sh` proves the native seams (required
fields, `tools:` / `sandbox_mode`, no model or effort pins, no unsupported
Claude nesting claim). Neither proves the semantics are right, and no test here
observes an actual dispatch.

Verifying real behaviour — that a role is launched, keeps its permission
boundary, and gets the requested model — needs an installed plugin plus runtime
event metadata (`subagent.started` / `subagent.completed`). That is a separate
integration seam, not part of this renderer. The Waza suites evaluate skills
that *describe* routing; they never load these artifacts.

Normalizing the divergent wording is blocked on that seam: collapsing four
wordings into one changes prompt behaviour, and nothing here can currently
observe a regression.

## Checks

From the repository root:

```bash
for test in tests/cheap-dev-workers-*.sh; do bash "$test"; done
bash tests/plugin-version-bump.sh
mise run lint
```

## Releases

Bump `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` together
whenever shipped files under this plugin directory change; plugin updates are
a no-op until the string changes (`../../docs/agents/harnesses.md`). Codex
personal agents are copies in `~/.codex/agents/`; after a release run root
`scripts/upgrade.sh --plugin cheap-dev-workers`.

The repository-root setup, upgrade, and uninstall scripts are the only public
lifecycle entry points. They detect installed plugin state before acting;
plugin-local scripts are internal post-action helpers.

## Routing contract

- Skills request roles, never plugin identities or provider models. Runtime
  adapters resolve them: Claude Code and Copilot CLI dispatch
  `cheap-dev-workers:<role>`; Codex requests the installed role name.
  Cursor CLI loads the same plugin agents and dispatches only the read-only
  roles; `check-runner` work stays in primary there because its `tools:`
  boundary is not enforced (`../../docs/agents/harnesses.md`).
- Choose the role before the model. Prefer an available named worker for
  bounded, context-heavy work. If the role is unavailable or unsupported,
  callers may use one generic worker only when they can reproduce its
  permission and task boundary. Explicit pre-execution dispatch/runtime errors
  such as capacity, rate-limit, rejected-model, or launch errors follow the same
  fallback; a generic pre-execution failure continues in primary. Once a worker
  begins its workload, its failure is the task result. If execution status is
  ambiguous, stop instead of risking duplicate work.
- When a named worker's tools cover only part of the work, split the part it
  can do and keep the rest in primary. Falling back to a generic worker for
  the whole task because one sub-question needs an unavailable tool defeats
  the routing contract.
- State the preference in each role's `description`, not only here. Runtimes
  surface the description to the dispatching agent and nothing else from this
  plugin, so a routing rule that lives only in this file cannot be followed.
- Keep architecture, implementation, scope, test selection, Git mutation, and
  remote-state decisions in primary.
- Limit a root task to four concurrent workers and one nested hop. No same-role
  recursion. Where plugin subagents cannot nest (Claude Code), primary relays
  `repo-explorer` → `check-runner` and `check-runner` → `log-summarizer`. Other
  runtimes may use the same paths only when supported.
- Pass minimum caller-scoped context. Potentially sensitive logs cross a model
  boundary only after `scripts/sanitize-log.sh` succeeds.

## Model choice

Claude, Codex, and Copilot role definitions leave model and reasoning effort
unset. Callers request the cheapest available model capable of each bounded
task and the lowest sufficient effort, starting routine work at `low`, when the
runtime supports per-dispatch selection. Otherwise the runtime inherits its
parent or configured defaults. Skills name no provider or model, so targets can
change without coupling workflow instructions.

The `agents/*.md` and `codex-agents/*.toml` definitions carry the same hard
rules and instructions in each runtime's native format. Both are rendered from
`roles/`, so they cannot be kept in sync by hand — edit the source and
re-render. A role's single `capability` becomes the `tools:` frontmatter and
the `sandbox_mode` together, with no runtime-specific tool list. A `read-only`
sandbox also renders `permissionMode: readonly`, the field Cursor CLI enforces
on plugin agents; `read+exec` renders none, since readonly blocks every shell
call. Read-only roles carry `permissionMode: readonly`, never `readonly: true`,
and `check-runner` carries neither; `tests/cheap-dev-workers-agents-content.sh`
enforces both.

Claude plugin subagents do not support `hooks` or `permissionMode`, so the
check-runner's Bash mutation boundary is prompt-enforced. The primary
supplies exact commands and treats an unexpected tracked-source change as
failure.

When dispatching these roles on Codex CLI, mind its dispatch gotchas (history
inheritance, relayed claims) in `../../docs/agents/harnesses.md`.

## Prevent Recurrence

- Propose a candidate only when you can name who hits it again, where, and on
  what change.
- On confirmation, offer the first tier that reaches them and only that one:
  enforce it (assert/type/test) with its size quoted, else a comment at that
  site, else the nearest existing topic document with a backtick-path pointer here
  and one sentence on why the tiers above cannot hold it.
- When adding to a file, audit the rest of it in the same pass; drop entries
  once tests or current documentation make them redundant.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md`
directly.
