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

## Windows

On Windows, run this skill's script through Git Bash (Git for Windows). A PATH
guard at the top of the script prepends the MSYS `usr/bin` so `find`/`tar` are not
shadowed by the native same-name tools; if a required POSIX tool is still missing,
the script aborts with an explicit error naming the missing tool.

## Commands

Discover the script path dynamically (do NOT hardcode):
1. Global scope: `~/.agents/skills/mem-sync/scripts/mem-sync-git.sh`
2. Project scope: `<repo>/skills/mem-sync/scripts/mem-sync-git.sh`
3. Fallback: search for `mem-sync-git.sh`.

- `mem-sync-git.sh pull` — record local WIP, fetch+rebase remote, copy back. Run at session start.
- `mem-sync-git.sh push` — same merge, then push. Run at session end or after promoting candidates.
- `mem-sync-git.sh` (no argument) — defaults to `status`.
- `mem-sync-git.sh status` — read-only: print the resolved remote/branch header, then summarize how local `.memories/` differs (in sync, or local-only / remote-only / modified files).
- `mem-sync-git.sh diff` — read-only: like `status` but prints the full unified diff (local vs remote).
- `mem-sync-git.sh print-branch` — print the derived per-user branch and exit (machine-readable, used by tooling/tests).
- `mem-sync-git.sh print-remote` — resolve and print just the sync remote (env → auto-detect) and exit (machine-readable). `status` already shows this; use `print-remote` when a script needs the bare value. Exits non-zero with guidance if the remote is ambiguous.

See [references/git-sync-workflow.md](references/git-sync-workflow.md) for mechanics,
anti-pollution rules, and conflict handling.

## Read-After-Sync Ordering

Run `pull`, `push`, and `compact` as exclusive operations against `.memories/`.
Do not read `.memories/` in parallel with those commands.

`pull` briefly removes and recreates the local `.memories/` directory while copying
the synchronized snapshot back from the isolated worktree. A parallel `grep`,
`Select-String`, `Get-Content`, `cat`, or similar read can observe that transient
missing-directory state and report a false error. Wait for the sync command to
finish successfully before scanning handoffs, candidates, or daily logs.

## Remote resolution

The sync remote is resolved in this order:

1. **`MEM_SYNC_REMOTE` env var** — explicit one-off override; highest priority, never persisted.
2. **Auto-detect** from the repo's own push configuration (not by remote name):
   - the current branch's push target resolved by Git itself
     (`git for-each-ref --format='%(push:remotename)'`: `branch.<name>.pushRemote` →
     `remote.pushDefault` → tracking remote) → use that remote, so memory follows wherever
     the repo actually pushes (e.g. a fork's writable remote), regardless of the name `origin`;
   - no push target configured but exactly one remote exists → use it;
   - no push target and multiple remotes → **ambiguous**: the command lists the remotes and
     exits non-zero. Give the current branch a push target (`git push -u <remote> <branch>`)
     or rerun with `MEM_SYNC_REMOTE=<name>`, then retry.

The remote is recomputed from live Git config on every run, so retargeting your push remote is
picked up automatically — there is no stored memory-sync remote to go stale.
The per-user branch name (`memories/<email-localpart>`) is unaffected by the remote choice.

If a command reports an ambiguous remote set, relay the printed remote list to the user and
ask which remote to use, then set a push target (or `MEM_SYNC_REMOTE=<name>`) before retrying.

## Anti-Pollution

Never commit `.memories/` to an ordinary development branch. If the user asks to
"commit memory" or "sync daily notes to Git", intercept and route through this syncer.
