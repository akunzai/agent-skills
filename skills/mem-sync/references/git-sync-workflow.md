# Git Memories Synchronization Workflow

This reference explains how to use the automated sync script to seamlessly synchronize daily logs (`.memories/`) across multiple machines without polluting the main branch or messing up your editor's workspace.

## 1. Dynamic Discovery Algorithm (For AI Agents)

Since this skill can be loaded in different scopes, **DO NOT hardcode the script path**. Determine the absolute path dynamically:

1. **User Scope Check**: If loaded globally, the script is at `~/.agents/skills/mem-sync/scripts/mem-sync-git.sh`.
2. **Project Scope Check**: If loaded locally, the script is at `<repo>/skills/mem-sync/scripts/mem-sync-git.sh`.
3. **Fallback Discovery**: If both checks fail, use workspace file search tools to search for `mem-sync-git.sh` in the workspace or `~/.agents/` directory.

## 2. Core Mechanics

Instead of switching your active working branch (which triggers editor resets and file reloading), the automated script uses **Git Worktrees** in the background:
- It creates a dedicated, isolated per-user branch named `memories/<email-localpart>` with no parent history (an orphan branch).
- It checks out this branch into a hidden workspace folder `.git/memories-worktree/`.
- **Anti-Loss Sync Rule (3-Way Rebase)**: When syncing, the script first records the local `.memories/` snapshot as a WIP commit inside the isolated worktree, then fetches and rebases onto `<remote>/memories/<email-localpart>` (the resolved sync remote). This lets Git merge concurrent daily-log edits without relying on filesystem modification times.
- **Deletion Semantics (push vs pull)**: `push` mirrors the local `.memories/` exactly, so a file removed locally is recorded as a deletion and propagates to other devices. `pull` is non-destructive: it overlays local WIP (new/modified files) onto the remote snapshot but never records a deletion for a file that is merely absent locally. This keeps a pull on a fresh device — or one whose `.memories/` was emptied by a local clean — from wiping the remote logs of other devices.
- **Conflict Safety**: If Git reports a rebase conflict, the script stops without copying conflicted files back to the local workspace. Resolve the conflict inside `.git/memories-worktree/`, run `git rebase --continue` or abort, then rerun sync.

## 3. Command Line Operations

You can run the script manually depending on the scope:

### Upload & Push Local Notes
```bash
# Example: Executing globally
~/.agents/skills/mem-sync/scripts/mem-sync-git.sh push
```

`push` also fetches and rebases remote updates before pushing. Even when there are no new local changes, it can still bring another device's latest daily logs back into the local `.memories/` directory.

### Download & Pull Remote Notes
```bash
# Example: Executing globally
~/.agents/skills/mem-sync/scripts/mem-sync-git.sh pull
```

`pull` records unpushed local daily notes before rebasing remote changes, so it is not a blind overwrite operation. Unlike `push`, it never propagates a local deletion: files absent locally are restored from the remote rather than removed from the branch.

### Inspect Differences (read-only)
```bash
# Per-file summary: in sync, or local-only / remote-only / modified
~/.agents/skills/mem-sync/scripts/mem-sync-git.sh status

# Full unified diff of local .memories/ vs the remote per-user branch
~/.agents/skills/mem-sync/scripts/mem-sync-git.sh diff
```

`status`/`diff` only fetch the per-user branch and compare it against the local
`.memories/` directory — they never modify the working copy, the worktree, or the remote.
If the remote branch does not exist yet, `status` reports how many local logs are unpushed.

## 3a. Remote Resolution

The remote is resolved as: `MEM_SYNC_REMOTE` env var → auto-detect. Auto-detect follows the
repo's **own push configuration** instead of guessing by remote name:

- it resolves the current branch's push target via Git itself
  (`git for-each-ref --format='%(push:remotename)'`, i.e. `branch.<name>.pushRemote` →
  `remote.pushDefault` → tracking remote) and uses that remote — so memory follows wherever
  this repo actually pushes (a fork's writable remote, etc.), independent of the name
  `origin`;
- if no push target is configured but exactly one remote exists → use it;
- otherwise (no push target and multiple remotes) → the command lists the remotes and
  aborts so nothing is pushed to the wrong place.

```bash
# Normal case: the remote is taken from where the current branch pushes.
git push -u myfork "$(git branch --show-current)"   # if not set up yet
~/.agents/skills/mem-sync/scripts/mem-sync-git.sh push

# One-off override for an ambiguous repo or a different target:
MEM_SYNC_REMOTE=memvault ~/.agents/skills/mem-sync/scripts/mem-sync-git.sh push
```

The remote is recomputed from live Git config each run, so retargeting your push remote is
picked up automatically — nothing is stored for memory sync to go stale. The env-sourced
remote is taken verbatim; read-only `status`/`diff` never write config. The resolved remote
must exist or the script aborts, naming the resolution source. The per-user branch name
(`memories/<email-localpart>`) is unaffected.

## 4. Automation Guidelines for AI Agents

Whenever you start a session or detect active git operations in a cross-device project environment:
- Proactively offer to execute `mem-sync-git.sh pull` (using the discovered path) to pull down notes recorded on other devices.
- Before ending a session or after promoting candidate memories, execute `mem-sync-git.sh push` to persist today's notes for other workspaces.

## Authoritative Compaction (`compact`)

`mem-sync-git.sh compact` rewrites the user's `memories/<email-localpart>` branch to a
single orphan commit containing only the current local `.memories/` files, then
force-pushes it. Use it for short-term cleanup (see the `mem-clean` skill): delete expired
logs locally, run `pull` first to gather all of this user's devices' logs, then `compact`.

Because it rewrites history, other devices detect the missing common ancestor on their next
`pull` and adopt the rewrite via `reset --hard` instead of rebasing — so deletions
propagate instead of resurrecting. This is per-user and never affects other developers.

## Anti-Pollution Rules

- Never commit `.memories/` to an ordinary development branch (`main`, `dev`, `feature/*`).
- If the user asks to "commit memory" or "sync daily notes to Git", intercept and
  explain that daily logs sync through the isolated per-user `memories/<email-localpart>`
  branch via this syncer, not the active branch.
- Always use `mem-sync-git.sh` (running inside the isolated memory worktree) to sync.
