# Agent Skills

[![skills.sh](https://skills.sh/b/akunzai/agent-skills)](https://skills.sh/akunzai/agent-skills)

My personal agent skills for AI coding assistants — compatible with Antigravity, Claude Code, Codex, and more.

## Install

```bash
npx skills add akunzai/agent-skills
```

## Skills

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


