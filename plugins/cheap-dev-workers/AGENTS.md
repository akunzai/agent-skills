# cheap-dev-workers Development

## Local setup

Claude Code auto-discovers `agents/` once the plugin is installed; no setup
script needed on that side.

Codex CLI has no plugin-bundled agent mechanism, so its subagents must be
copied into a personal or trusted-project agents directory:

```bash
bash scripts/setup.sh
```

This copies `codex-agents/*.toml` into `~/.codex/agents/` (personal scope
only — this plugin does not install into a project's `.codex/agents/`).

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
Codex personal agents are copies in `~/.codex/agents/`; after a release run
`scripts/uninstall.sh` then `scripts/setup.sh` (setup refuses to overwrite a
differing file).

## Routing contract

- Skills request roles, never plugin identities or provider models. Runtime
  adapters resolve them: Claude Code dispatches `cheap-dev-workers:<role>`;
  Codex requests the installed role name.
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

Claude and Codex role definitions leave model and reasoning effort unset.
Callers request the cheapest available model capable of each bounded task and
the lowest sufficient effort, starting routine work at `low`, when the runtime
supports per-dispatch selection. Otherwise the runtime inherits its parent or
configured defaults. Skills name no provider or model, so targets can change
without coupling workflow instructions.

The `agents/*.md` (Claude Code) and `codex-agents/*.toml` (Codex CLI)
definitions carry the same hard rules and instructions in each tool's native
format. Keep them in sync when editing either side.

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
