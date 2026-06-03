---
name: mem-clean
description: Interactively clean short-term memory — delete expired project/global daily logs (.memories/YYYY-MM-DD.md) under a confirmed retention plan, and resolve cloud-drive conflict copies. Destructive; always requires a dry-run plan and explicit user confirmation.
---

# mem-clean — Short-Term Memory Cleanup

Removes expired daily logs and tidies cloud-sync conflict copies. Every action is
interactive: produce a dry-run plan and get explicit confirmation before deleting.

## What it cleans

- **Expired project logs** in `<repo>/.memories/YYYY-MM-DD.md` — see
  [references/short-term-cleanup.md](references/short-term-cleanup.md).
- **Expired global logs** in `~/.agents/memories/YYYY-MM-DD.md` — deleted directly
  (not git-synced; see the reference).
- **Cloud conflict copies** (`*Conflict*` / `*conflicted*`) in `~/.agents/` — see
  [references/cloud-conflict-resolver.md](references/cloud-conflict-resolver.md).

## Rules (summary)

- Default retention is 30 days, computed from the `YYYY-MM-DD.md` filename, never mtime.
- Block cleanup of files with an open `[Handoff]` (no later `[Handoff:done]`) or with
  unresolved `[Candidate]` entries (not `[Promoted]`, `[Rejected]`, or `[Expired]`).
- Project cleanup is per-user: after deleting expired logs locally, run
  `/mem-sync` first, then `mem-sync-git.sh compact` to rewrite the user's
  `memories/<email-localpart>` branch to a single commit and force-push. Other devices
  adopt it on next pull.
- Always show the dry-run plan (scope, retention window, delete list, blocked files,
  user keep-list) and require explicit confirmation.
