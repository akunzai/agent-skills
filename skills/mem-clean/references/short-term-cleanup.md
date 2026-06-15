# Short-Term Memory Cleanup Specifications

This reference defines how to clean short-term daily memory logs safely. It applies to project logs in `.memories/YYYY-MM-DD.md` and global logs in `~/.agents/memories/YYYY-MM-DD.md`.

## 1. Default Retention

- Default retention is **30 days**.
- A log is expired when its filename date is older than the retention window.
- Never infer retention from file modification time; use the `YYYY-MM-DD.md` filename.
- Treat malformed filenames as out of scope for automatic deletion. Report them to the user instead.

## 2. Confirmation Requirement

Short-term cleanup is destructive and must be interactive:

1. Scan the target scope and compute the cleanup plan.
2. Show the user:
   - The target scope: project or global.
   - The retention window.
   - The exact files that would be deleted.
   - Any files blocked from cleanup.
   - Any user-specified keep list.
3. Ask for explicit confirmation before execution.
4. Do not clean anything if the user does not confirm.

If the user asks to retain specific memory entries or files, preserve those items even when they are older than the retention window.

## 3. Eligibility Checks

Before deleting or compacting a daily log:

- Block cleanup for daily logs containing unresolved `[Candidate]` entries that are not marked `[Promoted]`, `[Rejected]`, or `[Expired]`.
- Do not clean `.memories/handoffs/` files here: active handoffs are owned by `mem-auto`, which deletes each task's file on completion. Only remove a handoff file when the user confirms its task is abandoned.
- Prefer marking old candidates as `[Expired]` with user confirmation before cleanup.
- Redact sensitive content immediately if discovered; do not wait for the normal retention window.

### Candidate Resolution Markers

A `[Candidate]` blocks cleanup of its file until it is resolved to one of:

- `[Promoted]` — written by the promotion flow when the user approves promotion.
- `[Rejected]` — written when the user declines to promote a candidate.
- `[Expired]` — written here, with user confirmation, for stale candidates that were
  never promoted or rejected, so cleanup is not blocked indefinitely.

Prefer marking stale candidates `[Expired]` (with confirmation) before deleting their log.

## 4. Project Scope Cleanup

Project short-term memory lives in `<repo>/.memories/` and syncs through the isolated
per-user branch `memories/<email-localpart>` (see the `mem-sync` skill).

After user confirmation:

1. Run `/mem-sync` (`mem-sync-git.sh pull`) first so the user's branch has collected
   logs from all of this user's devices.
2. Delete expired eligible logs from local `.memories/`.
3. Run `mem-sync-git.sh compact` to rebuild the user's `memories/<email-localpart>`
   branch as a single commit containing only retained `.memories/` files and force-push it.
4. Other devices adopt the rewrite automatically on their next `mem-sync-git.sh pull`
   (the syncer detects the rewritten remote and `reset --hard`s to it).

This rewrite is authoritative and per-user: it never affects other developers' branches.
Do not commit `.memories/` to the active development branch.

## 5. Global Scope Cleanup

Global short-term memory lives in `~/.agents/memories/`.

After user confirmation:

1. Delete expired eligible `~/.agents/memories/YYYY-MM-DD.md` files directly.
2. Preserve any files or entries the user explicitly asked to keep.
3. Report deleted files and retained exceptions.

Global cleanup does not use any git branch; it deletes files directly.

## 6. Dry Run Output

Before asking for confirmation, present a dry-run summary in this shape:

```text
Short-term cleanup plan
Scope: project
Retention: 30 days
Delete:
- .memories/2026-04-20.md
Keep:
- .memories/2026-05-28.md (inside retention)
Blocked:
- .memories/2026-04-18.md (open handoff)
- .memories/2026-04-19.md (unresolved candidate)
Requires confirmation: yes
```

Execution may proceed only after the user confirms this plan.
