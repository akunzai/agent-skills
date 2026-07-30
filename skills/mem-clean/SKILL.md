---
name: mem-clean
description: Interactively clean short-term memory — delete expired project/global daily logs (.memories/YYYY-MM-DD.md) under a confirmed retention plan, and resolve cloud-drive conflict copies. Destructive; always requires a dry-run plan and explicit user confirmation.
---

# mem-clean — Short-Term Memory Cleanup

## What it cleans

- **Expired project logs** in `~/.agents/memories/projects/<proj-slug>/YYYY-MM-DD.md` — see
  [references/short-term-cleanup.md](references/short-term-cleanup.md).
- **Expired global logs** in `~/.agents/memories/YYYY-MM-DD.md` — deleted directly.
- **Cloud conflict copies** (`*Conflict*` / `*conflicted*`) in `~/.agents/` — see
  [references/cloud-conflict-resolver.md](references/cloud-conflict-resolver.md).

## Rules (summary)

- Default retention is 30 days, computed from the `YYYY-MM-DD.md` filename, never mtime.
- Block cleanup of daily logs with unresolved `[Candidate]` entries (not `[Promoted]`,
  `[Rejected]`, or `[Expired]`).
- Leave handoff files alone unless the user explicitly confirms a task is abandoned.
- Always show the dry-run plan (scope, retention window, delete list, blocked files,
  user keep-list) and require explicit confirmation.
