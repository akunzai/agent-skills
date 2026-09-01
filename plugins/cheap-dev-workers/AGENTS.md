# cheap-dev-workers Development

## Local setup

Claude Code auto-discovers `agents/` once the plugin is installed; no setup
script needed on that side.

GitHub Copilot CLI also auto-discovers `agents/` from the installed plugin,
reading the same `.claude-plugin` manifests — no Copilot-specific copy of the
role definitions exists. From the repository root, install it without touching
Codex agents with:

```bash
bash scripts/setup.sh --plugin cheap-dev-workers
```

Select GitHub Copilot CLI in the interactive installer. Scripts and CI may use
`--runtime copilot --yes`. See @../../docs/agents/copilot-cli.md.

Codex CLI has no plugin-bundled agent mechanism, so its subagents must be
copied into a personal or trusted-project agents directory:

```bash
bash scripts/setup.sh --plugin cheap-dev-workers
```

Select Codex CLI in the interactive installer. This copies
`codex-agents/*.toml` into `~/.codex/agents/` (personal scope only — this
plugin does not install into a project's `.codex/agents/`).

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
- `runtime` — deliberately different because the runtimes differ (Claude plugin
  subagents cannot nest; Codex allows one hop)
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
whenever shipped files under this plugin directory change. Claude Code uses
that string as the update cache key, so `claude plugin update` is a no-op
until it changes. See [version management](https://code.claude.com/docs/en/plugins-reference#version-management).
Copilot uses the same `.claude-plugin/plugin.json` version string as its
update key. Codex personal agents are copies in `~/.codex/agents/`; after a
release run root `scripts/upgrade.sh --plugin cheap-dev-workers`.

The repository-root setup, upgrade, and uninstall scripts are the only public
lifecycle entry points. They detect installed plugin state before acting;
plugin-local scripts are internal post-action helpers.

## Routing contract

- Skills request roles, never plugin identities or provider models. Runtime
  adapters resolve them: Claude Code and Copilot CLI dispatch
  `cheap-dev-workers:<role>`; Codex requests the installed role name.
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
  recursion. Claude plugin subagents cannot nest, so primary relays
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

The `agents/*.md` (Claude Code and Copilot CLI) and `codex-agents/*.toml`
(Codex CLI) definitions carry the same hard rules and instructions in each
tool's native format. Both are rendered from `roles/`, so they cannot be kept
in sync by hand — edit the source and re-render. A role's single `capability`
becomes the `tools:` frontmatter and the `sandbox_mode` together; Copilot maps
that `tools:` list onto its own tool names, so the permission boundary survives
without a Copilot-specific list.

Claude plugin subagents do not support `hooks` or `permissionMode`, so the
check-runner's Bash mutation boundary is prompt-enforced. The primary supplies
exact commands and treats an unexpected tracked-source change as failure.

## Codex CLI dispatch gotchas

- [codex-cli] A prompt that both names an `agent_type` and asks the
  orchestrator to fully inherit conversation history gets rejected by
  Codex's collaboration layer. Dispatch these agents without full history
  inheritance (e.g. `fork_turns: none`) instead.
- [codex-cli] The root session relays whatever the subagent's final message
  claims (counts, exit codes) without independently checking raw output.
  Ask explicitly for the subagent's raw output when the claim matters,
  rather than trusting the root session's summary of it.

## Self-Reflection

- Propose concise, non-obvious candidates before recording them.
- On confirmation, store them in the nearest existing topic document and add
  an `@path` pointer here; prune facts once tests or current documentation
  make them redundant.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md`
directly.
