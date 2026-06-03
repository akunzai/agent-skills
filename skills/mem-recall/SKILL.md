---
name: mem-recall
description: Search short-term memory on demand — project .memories/ and ~/.agents/memories/ for handoffs, candidates, and prior task state not already loaded by AGENTS.md / CLAUDE.md.
---

# mem-recall — On-Demand Memory Search

Retrieves short-term context: recent daily logs, candidates, and open handoffs.
Durable instructions should come from auto-loaded `AGENTS.md` / `CLAUDE.md`; suggest
referencing `~/.agents/MEMORY.md` from `~/.agents/AGENTS.md` or `~/.claude/CLAUDE.md`
when the runtime supports it.

## How to recall

```bash
# Recent project daily logs
grep -rn "pattern" .memories/ 2>/dev/null

# Recent global daily logs
grep -rn "pattern" ~/.agents/memories/ 2>/dev/null

# Newest open handoff to resume (one without a later [Handoff:done])
grep -rn "\[Handoff" .memories/ 2>/dev/null | tail
```

## Guidance

- In a cross-device setup, run `/mem-sync` (pull) first so you read the freshest logs.
- Focus recall on short-term logs. Do not re-read `AGENTS.md` / `CLAUDE.md` just because the skill is active; coding agents normally load them as project instructions.
- Search `~/.agents/MEMORY.md`, `AGENTS.md`, or `CLAUDE.md` only when the auto-loaded
  instructions seem incomplete or you need exact wording.
- When resuming work, surface the newest open `[Handoff]` block and confirm with the user
  before continuing (the `mem-auto` autopilot does this at session start).
