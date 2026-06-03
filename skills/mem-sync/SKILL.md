---
name: mem-sync
description: Synchronize project daily memory logs (.memories/) across devices over Git using an isolated per-user branch and worktree, without polluting the active development branch. Use to pull other devices' logs at session start and push local logs at session end.
---

# mem-sync — Cross-Device Memory Sync

Synchronizes `<repo>/.memories/` across machines through a dedicated, isolated
per-user branch `memories/<email-localpart>` using a background git worktree, so the
active development branch and your editor workspace are never disturbed.

## Per-User Branch

The sync branch is derived from `git config user.email`: the part before `@`,
lowercased and slugified (non-alphanumeric runs become `-`). `User@Example.com` →
`memories/user`. Each user pushes/pulls only their own branch, so two developers on
the same repo never collide on same-date log filenames.

## Commands

Discover the script path dynamically (do NOT hardcode):
1. Global scope: `~/.agents/skills/mem-sync/scripts/mem-sync-git.sh`
2. Project scope: `<repo>/skills/mem-sync/scripts/mem-sync-git.sh`
3. Fallback: search for `mem-sync-git.sh`.

- `mem-sync-git.sh pull` — record local WIP, fetch+rebase remote, copy back. Run at session start.
- `mem-sync-git.sh push` — same merge, then push. Run at session end or after promoting candidates.
- `mem-sync-git.sh` (no argument) — defaults to `status`.
- `mem-sync-git.sh status` — read-only: fetch the per-user branch and summarize how local `.memories/` differs (in sync, or local-only / remote-only / modified files).
- `mem-sync-git.sh diff` — read-only: like `status` but prints the full unified diff (local vs remote).
- `mem-sync-git.sh print-branch` — print the derived per-user branch and exit (used by tooling/tests).

See [references/git-sync-workflow.md](references/git-sync-workflow.md) for mechanics,
anti-pollution rules, and conflict handling.

## Remote override

The sync remote defaults to `origin`. In a forked open-source repo — where `origin` may be
your public fork, or you'd rather keep daily logs on a private remote — set the
`MEM_SYNC_REMOTE` environment variable to an existing remote name:

```bash
git remote add memvault git@example.com:me/private-notes.git
MEM_SYNC_REMOTE=memvault mem-sync-git.sh push
```

The named remote must already exist; the script aborts with a clear error otherwise. All
operations (`push`/`pull`/`compact`/branch init) then target that remote. The per-user
branch name is unaffected.

## Anti-Pollution

Never commit `.memories/` to an ordinary development branch. If the user asks to
"commit memory" or "sync daily notes to Git", intercept and route through this syncer.
