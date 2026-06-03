---
name: mem-recall
description: Search and load past memory on demand across scopes — global preferences (~/.agents/MEMORY.md), project conventions (AGENTS.md / CLAUDE.md), and recent daily logs (.memories/). Use when you need prior context, preferences, decisions, or an open handoff to resume.
---

# mem-recall — On-Demand Memory Search

Retrieves relevant prior context when preferences, conventions, or task state are needed.

## How to recall

```bash
# Durable preferences and project rules
grep -rn "pattern" ~/.agents/MEMORY.md AGENTS.md CLAUDE.md

# Recent project daily logs
grep -rn "pattern" .memories/ 2>/dev/null

# Newest open handoff to resume (one without a later [Handoff:done])
grep -rn "\[Handoff" .memories/ 2>/dev/null | tail
```

## Guidance

- In a cross-device setup, run `/mem-sync` (pull) first so you read the freshest logs.
- Prefer the most specific scope: project rules over global preferences when both apply.
- When resuming work, surface the newest open `[Handoff]` block and confirm with the user
  before continuing (the `mem-auto` autopilot does this at session start).
