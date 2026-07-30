---
name: mem-recall
description: Search short-term memory on demand — global project memories (~/.agents/memories/projects/<proj-slug>/) and ~/.agents/memories/ for candidates and prior task state not already loaded by AGENTS.md / CLAUDE.md.
---

# mem-recall — On-Demand Memory Search

Retrieves short-term context: recent daily logs, candidates, and historical task state.

## How to recall

```bash
# Resolve global project memory directory
PROJ_MEM_DIR="$(skills/mem-auto/scripts/resolve-proj-memory-path.sh)"

# Recent project daily logs
grep -rn "pattern" "$PROJ_MEM_DIR" 2>/dev/null

# Recent global daily logs
grep -rn "pattern" ~/.agents/memories/ 2>/dev/null

# Open handoffs (if present in global project directory)
ls "$PROJ_MEM_DIR/handoffs/" 2>/dev/null
```

## Guidance

- Scope by recency: read newest daily logs first and limit to recent days. Use `grep` to extract matching lines — do not read whole daily logs or entire directories into context.
- Focus recall on short-term logs. Do not re-read `AGENTS.md` / `CLAUDE.md` just because the skill is active; coding agents already load them as project instructions — open them only if the loaded copy looks incomplete or you need exact wording.
- Session handoffs are handled primarily by dedicated handoff skills; `mem-recall` surfaces legacy or global project handoffs on demand.

