---
name: mem-recall
description: Search short-term memory on demand — project .memories/ and ~/.agents/memories/ for handoffs, candidates, and prior task state not already loaded by AGENTS.md / CLAUDE.md.
---

# mem-recall — On-Demand Memory Search

Retrieves short-term context: recent daily logs, candidates, and open handoffs.
Durable instructions come from auto-loaded `AGENTS.md` / `CLAUDE.md`, so this skill stays
focused on short-term memory.

## How to recall

```bash
# Recent project daily logs
grep -rn "pattern" .memories/ 2>/dev/null

# Recent global daily logs
grep -rn "pattern" ~/.agents/memories/ 2>/dev/null

# Open handoffs to resume — one file per active task, newest creation day last
ls .memories/handoffs/ 2>/dev/null
```

## Guidance

- In a cross-device setup, run `/mem-sync` (pull) first so you read the freshest logs.
- Scope by recency: read newest daily logs first and limit to recent days. Use `grep` to extract matching lines — do not read whole daily logs or the entire `.memories/` directory into context.
- Focus recall on short-term logs. Do not re-read `AGENTS.md` / `CLAUDE.md` just because the skill is active; coding agents already load them as project instructions — open them only if the loaded copy looks incomplete or you need exact wording.
- When resuming work, list the open handoff files under `.memories/handoffs/`, surface the
  relevant one, and confirm with the user before continuing (the `mem-auto` autopilot does
  this at session start).
