# Agent Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/akunzai/agent-skills/actions/workflows/tests.yml/badge.svg)](https://github.com/akunzai/agent-skills/actions/workflows/tests.yml)
[![skills.sh](https://skills.sh/b/akunzai/agent-skills)](https://skills.sh/akunzai/agent-skills)

My personal agent skills for AI coding assistants — compatible with Antigravity, Claude Code, Codex, and more.

## Why

AI coding assistants are powerful out of the box, but they lack persistent memory
and opinionated workflows across sessions. This project fills that gap with
reusable skills that give your assistant long-term memory, cleaner
git history, and better project awareness — without manual setup every time.

## Install

```bash
npx skills add akunzai/agent-skills
```

## Skills

### [`tidy-commits`](skills/tidy-commits/SKILL.md)

Clean up local git commit history before review or merge. Use it to turn WIP,
fixup, review-fix, format-only, poorly ordered, unsigned, or poorly messaged
commits into a clear, verified branch story.

### [`pr-workflow`](skills/pr-workflow/SKILL.md)

Standard operating procedure for preparing, opening, and managing Pull Requests (PR) and Merge Requests (MR) safely with preflight checks, commit scoping, and issue auto-closing rules.

### [`github-epic`](skills/github-epic/SKILL.md)

Manage multi-issue epics, parent-child task hierarchies, and blocking dependencies natively on GitHub (`gh api ... sub_issues` and `dependencies/blocked_by`).

### [`gitlab-epic`](skills/gitlab-epic/SKILL.md)

Manage multi-issue epics and task hierarchies on GitLab (supporting Premium/Ultimate native epics and Free/CE tier label & markdown emulation).

### [`agents-md`](skills/agents-md/SKILL.md)

Audit, create, and improve `AGENTS.md` files to give AI assistants persistent project memory.

Use it when you want to:

- Bootstrap an `AGENTS.md` for a new project
- Audit and score an existing `AGENTS.md` for quality
- Keep `AGENTS.md` in sync with Claude Code via a `CLAUDE.md` symlink
- Automatically write discovered knowledge back to `AGENTS.md` after solving problems

### [`mem-auto`](skills/mem-auto/SKILL.md)

Autopilot memory governance umbrella. Captures verified candidate notes to global project memory, and delegates manual work to the commands below.

- [`mem-recall`](skills/mem-recall/SKILL.md) — search/load past context on demand
- [`mem-promote`](skills/mem-promote/SKILL.md) — promote candidates to durable memory; prune duplicates
- [`mem-clean`](skills/mem-clean/SKILL.md) — clean expired short-term logs; resolve cloud conflicts
- [`mem-sync`](skills/mem-sync/SKILL.md) — (DEPRECATED) project short-term memory is now stored globally without Git sync operations
- [`mem-setup`](skills/mem-setup/SKILL.md) — bridge every installed agent's global memory to one canonical `~/.agents/AGENTS.md`

### [`mise`](skills/mise/SKILL.md)

Manage a project's toolchain, language runtimes, and tasks through a single
committed `mise.toml`. Captures opinionated conventions for pinning, built-in
backends, tasks over scripts, and phased host → CI → container adoption.

### [`aube`](skills/aube/SKILL.md)

Use [aube](https://aube.jdx.dev/) as the Node.js package manager, installed and
pinned through mise. Covers `aubr`/`aube ci` workflows, lockfile policy, the
lifecycle-script jail, and migrating from pnpm/npm/bun.

### [`agentsview-extract`](skills/agentsview-extract/SKILL.md)

Analyze conversation history across AI agents using `agentsview` (CLI or MCP) to extract reusable gotchas/preferences into `AGENTS.md` or construct new skills.


## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines on how to get started.

## License

This project is licensed under the [MIT License](LICENSE).
