# Agent Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/akunzai/agent-skills/actions/workflows/tests.yml/badge.svg)](https://github.com/akunzai/agent-skills/actions/workflows/tests.yml)

My personal agent skills for AI coding assistants — compatible with Antigravity, Claude Code, Codex, and more.
Those assistants can load the skills; **effectiveness is measured only on
GitHub Copilot** via [Waza](https://github.com/microsoft/waza). See
[docs/evals/waza.md](docs/evals/waza.md).

## Why

AI coding assistants are powerful out of the box, but they lack persistent memory
and opinionated workflows across sessions. This project fills that gap with
reusable skills grouped into four areas: **Memory** (durable project context
that survives across sessions), **Git** (clean commit history and safe PR/issue
workflows), **Toolchain** (pinned, opinionated tool and dependency
management), and **Testing** (framework-agnostic test generation and
validation workflows).

## Install

Install and manage skills across agents with [Skills Manager](https://github.com/akunzai/skills-manager):

```bash
skills add akunzai/agent-skills
```

Alternatively, install via `npx skills`:

```bash
npx skills add akunzai/agent-skills
```

The interactive picker groups the catalog as **Charley Skills**. The same set
is also a Claude Code plugin:

```bash
claude plugin marketplace add akunzai/agent-skills
claude plugin install charley-skills@akunzai-agent-skills --scope user
```

GitHub Copilot CLI reads the same marketplace manifest:

```bash
copilot plugin marketplace add akunzai/agent-skills
copilot plugin install charley-skills@akunzai-agent-skills
```

## Skills

### Git

#### [`tidy-commits`](skills/tidy-commits/SKILL.md)

Clean up local git commit history before review or merge. Use it to turn WIP,
fixup, review-fix, format-only, poorly ordered, unsigned, or poorly messaged
commits into a clear, verified branch story.

#### [`pr-workflow`](skills/pr-workflow/SKILL.md)

Standard operating procedure for preparing, opening, and managing Pull Requests (PR) and Merge Requests (MR) safely with preflight checks, commit scoping, and issue auto-closing rules.

#### [`github-epic`](skills/github-epic/SKILL.md)

Manage multi-issue epics, parent-child task hierarchies, and blocking dependencies natively on GitHub (`gh api ... sub_issues` and `dependencies/blocked_by`).

#### [`gitlab-epic`](skills/gitlab-epic/SKILL.md)

Manage multi-issue epics and task hierarchies on GitLab (supporting Premium/Ultimate native epics and Free/CE tier label & markdown emulation).

### Memory

#### [`agents-md`](skills/agents-md/SKILL.md)

Audit, create, slim, and maintain `AGENTS.md` as a small index: one-sentence
project description, non-default package manager, non-standard commands, and
pointers. Spends the instruction budget on every-task facts; offloads the rest.

Use it when you want to:

- Bootstrap an `AGENTS.md` from repo evidence (not an init-script dump)
- Audit, score, and slim an existing `AGENTS.md` (contradictions, bloat, micromanagement)
- Keep `AGENTS.md` in sync with Claude Code via a `CLAUDE.md` symlink
- Surface discovered knowledge (gotchas, quirks) as a candidate after solving
  a problem, then write it back to `AGENTS.md`'s references once you confirm
  it

#### [`to-memory`](skills/to-memory/SKILL.md)

Explicitly record something worth remembering — decides scope (global vs.
project) and tier (short-term candidate vs. long-term durable), then writes it.
Autonomous knowledge capture after solving a problem stays with `agents-md`'s
Self-Reflection mechanism.

> **Migration:** The original `memory` skill was split into the `mem-*` family
> (`mem-auto`, `mem-clean`, `mem-promote`, `mem-recall`, `mem-setup`, and
> `mem-sync`), then consolidated into `to-memory`. These legacy names may remain
> visible in public registries because of historical install data, but are no longer
> maintained.

#### [`agentsview-extract`](skills/agentsview-extract/SKILL.md)

Persist gotchas, preferences, or a repeated workflow from recorded agent history into `AGENTS.md` or a new skill. After confirmation, installs AgentsView and the official `agentsview-finding-history` skill when they are missing.

#### [`agentsview-resume`](skills/agentsview-resume/SKILL.md)

Take over an unfinished session recorded by AgentsView — from another
agent, another project, or another machine. Delegates the transcript
read to a subagent, returns a bounded handoff, verifies it against the
current repository, then stops for your call.

### Toolchain

#### [`mise`](skills/mise/SKILL.md)

Manage a project's toolchain, language runtimes, and tasks through a single
committed `mise.toml`. Captures opinionated conventions for pinning, built-in
backends, tasks over scripts, and phased host → CI → container adoption.

#### [`aube`](skills/aube/SKILL.md)

Use [aube](https://aube.jdx.dev/) as the Node.js package manager, installed and
pinned through mise. Covers `aubr`/`aube ci` workflows, lockfile policy, the
lifecycle-script jail, and migrating from pnpm/npm/bun.

### Testing

#### [`backfill-unit-tests`](skills/backfill-unit-tests/SKILL.md)

Detect an existing codebase's test framework and backfill unit test
coverage for gaps, validating each generated test builds, is
CI-discoverable, and actually fails on broken code. For interactive
feature-first development, use `tdd` instead.

#### [`write-e2e-tests`](skills/write-e2e-tests/SKILL.md)

Turn a browser UI flow into a durable, checked-in Playwright Test e2e
spec. Unblocks a missing Playwright toolchain or
[webwright](https://github.com/microsoft/Webwright) run after
confirmation, converts Critical Points to assertions, and validates the
result is stable and CI-discoverable.

## Plugins

Separate from the skills above (not installable via `skills add` or `npx skills add`):

- [`codexbar-quota-handoff`](plugins/codexbar-quota-handoff/README.md) — a
  Claude Code / Codex CLI / GitHub Copilot CLI plugin and Grok Build hook that
  reminds you to wrap up when
  [CodexBar](https://github.com/steipete/CodexBar) detects that tool's
  own quota is nearly exhausted. Machine-specific (depends on your own
  CodexBar installation and account authorization) rather than something a
  visitor installs directly.
- [`cheap-dev-workers`](plugins/cheap-dev-workers/README.md) — four narrow,
  cheap-model workers for repository evidence, verification, safe-log
  summaries, and caller-scoped commit or PR drafting on Claude Code, Codex,
  and GitHub Copilot CLI.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines on how to get started.

## License

This project is licensed under the [MIT License](LICENSE).
