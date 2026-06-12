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

### [`agents-md`](skills/agents-md/SKILL.md)

Audit, create, and improve `AGENTS.md` files to give AI assistants persistent project memory.

Use it when you want to:

- Bootstrap an `AGENTS.md` for a new project
- Audit and score an existing `AGENTS.md` for quality
- Keep `AGENTS.md` in sync with Claude Code via a `CLAUDE.md` symlink
- Automatically write discovered knowledge back to `AGENTS.md` after solving problems

### [`mem-auto`](skills/mem-auto/SKILL.md)

Autopilot memory governance umbrella. Restores open handoffs at session start, captures
verified candidate notes, writes handoff blocks at boundaries, and delegates manual work
to the commands below.

- [`mem-recall`](skills/mem-recall/SKILL.md) — search/load past context on demand
- [`mem-promote`](skills/mem-promote/SKILL.md) — promote candidates to durable memory; prune duplicates
- [`mem-clean`](skills/mem-clean/SKILL.md) — clean expired short-term logs; resolve cloud conflicts
- [`mem-sync`](skills/mem-sync/SKILL.md) — sync daily logs across devices via a per-user branch
- [`mem-setup`](skills/mem-setup/SKILL.md) — bridge every installed agent's global memory to one canonical `~/.agents/AGENTS.md`

## Compatibility

| AI Assistant | Supported |
| --- | --- |
| [Antigravity](https://antigravity.google/) | ✅ |
| [Claude Code](https://docs.claude.ai/code/overview) | ✅ |
| [Codex](https://github.com/openai/codex) | ✅ |
| [OpenCode](https://opencode.ai/) | ✅ |

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines on how to get started.

## License

This project is licensed under the [MIT License](LICENSE).
