# Agent Skills

[![skills.sh](https://skills.sh/b/akunzai/agent-skills)](https://skills.sh/akunzai/agent-skills)

My personal agent skills for AI coding assistants — compatible with Antigravity, Claude Code, Codex, and more.

## Install

```bash
npx skills add akunzai/agent-skills
```

## Skills

### [`agents-md-improver`](skills/agents-md-improver/)

Audit, create, and improve `AGENTS.md` files to give AI assistants persistent project memory.

Use it when you want to:
- Bootstrap an `AGENTS.md` for a new project
- Audit and score an existing `AGENTS.md` for quality
- Keep `AGENTS.md` in sync with Claude Code via a `CLAUDE.md` symlink
- Automatically write discovered knowledge back to `AGENTS.md` after solving problems

### [`memory`](skills/memory/)

Unified autopilot memory governance system for both project and user scopes.

Use it when you want to:
- Retrieve and query past context, preferences, or technical pitfalls across scopes
- Automatically capture key learnings and newly verified coding patterns during sessions
- Proactively promote verified daily candidate memories to durable `MEMORY.md` with interactive confirmation
- Proactively audit, prune, and consolidate duplicate or obsolete conventions in long-term memory
- Detect and resolve cloud synchronization conflicts (e.g., Google Drive conflict files) within `~/.agents/`


