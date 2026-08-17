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
mise run lint
```

## Routing contract

- Skills request roles, never plugin identities or provider models. Runtime
  adapters resolve them: Claude Code dispatches `cheap-dev-workers:<role>`;
  Codex requests the installed role name.
- Prefer an available named worker only for bounded, context-heavy work. If
  dispatch is unavailable or fails to launch, continue in primary without
  probing configuration. A launched worker's failure is its task result.
- Keep architecture, implementation, scope, test selection, Git mutation, and
  remote-state decisions in primary.
- Limit a root task to four concurrent workers and one nested hop. No same-role
  recursion. Claude plugin subagents cannot nest, so primary relays
  `repo-explorer` → `check-runner` and `check-runner` → `log-summarizer`. Other
  runtimes may use the same paths only when supported.
- Pass minimum caller-scoped context. Potentially sensitive logs cross a model
  boundary only after `scripts/sanitize-log.sh` succeeds.

## Model choice

All four roles use Claude Haiku or Codex `gpt-5.6-luna`. Skills stay
model-agnostic so targets can change without coupling workflow instructions.

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
