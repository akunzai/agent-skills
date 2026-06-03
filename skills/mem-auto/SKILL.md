---
name: mem-auto
description: Autopilot memory governance umbrella — at session start restores the newest open [Handoff], captures verified [Candidate] notes during work, writes handoff blocks at boundaries, and closes handoffs. Delegates manual work to /mem-recall, /mem-promote, /mem-clean, /mem-sync. Use as the master memory manager.
---

# Unified Memory Autopilot

A unified, self-governing memory system that automatically retrieves, structures, and prunes project and user-level developer knowledge.

## Directory Structure

- **User Scope (Global Workspace)**: `~/.agents/`
  - Long-term memory: global durable preferences in `~/.agents/MEMORY.md` (Do NOT commit to Git).
  - Short-term memory: daily `[Candidate]` logs in `~/.agents/memories/YYYY-MM-DD.md`.
- **Project Scope (Local Repository)**: `<repo>/`
  - Long-term memory: local durable rules and conventions in `<repo>/AGENTS.md` (or `CLAUDE.md`, MUST commit to Git).
  - Short-term memory: daily logs in `<repo>/.memories/YYYY-MM-DD.md` holding `[Candidate]` and `[Handoff]` entries (untracked on dev branches; synced via the `mem-sync` skill's per-user `memories/<email-localpart>` branch).

## Quick start

```bash
# Search global preferences or project rules (AGENTS.md or CLAUDE.md)
grep -rn "pattern" ~/.agents/ AGENTS.md CLAUDE.md

# Log a candidate to today's daily log (include time stamp)
mkdir -p .memories
echo "- [Candidate] Preferred database is PostgreSQL. [04:05]" >> .memories/2026-06-02.md

# Check recent daily logs for an open [Handoff] to resume (one without a later [Handoff:done])
grep -rn "\[Handoff" .memories/ 2>/dev/null | tail
```

## Delegated commands

The umbrella runs the automatic loop and points you to these for manual work:

- **`/mem-recall`** — search/load past context on demand.
- **`/mem-promote`** — promote `[Candidate]` notes to durable memory; prune duplicates.
- **`/mem-clean`** — clean expired short-term logs; resolve cloud-drive conflicts.
- **`/mem-sync`** — pull/push daily logs across devices (per-user branch).

## Workflows

### The Autopilot Governance Loop

Coding agents must actively run this governance cycle during sessions and checkpoints:

- [ ] **1. Session Initialization (Handoff In)**:
  - **Read [references/session-handoff.md](references/session-handoff.md)** to inspect active task state restoration rules.
  - In a cross-device setup, pull first (see step 4) so you read the latest logs, not a stale local copy.
  - Scan recent daily logs (`.memories/YYYY-MM-DD.md`) for the newest `[Handoff]` block that has no matching `[Handoff:done]` closure, and resume from it. If several are open (e.g., parallel worktrees), list them and let the user pick.
  - Treat a stale open handoff (several days old, or its branch already merged/gone) as suspect: ask before resuming rather than blindly continuing.
  - Automatically query other memory files (`AGENTS.md`, `CLAUDE.md`, `MEMORY.md`) whenever preferences or conventions are unknown.
  - For ad-hoc lookups during the session, use **`/mem-recall`**.
- [ ] **2. Proactive Capture & Handoff (Handoff Out)**:
  - **Read [references/security.md](references/security.md)** and **[references/session-handoff.md](references/session-handoff.md)** before writing task states.
  - At milestones, quota resets, or session boundaries, append a `[Handoff]` block to today's log capturing the current task state. Append a fresh block rather than rewriting earlier ones; the newest open block for a task is its current state.
  - Preserve only facts a fresh agent would need to continue: current goal, implemented progress, verification status, next actions, blockers, and suggested skills to invoke next.
  - Reference existing artifacts by path or URL instead of duplicating their contents.
  - Treat `[Handoff]` entries as transient active state: they are not `[Candidate]` entries, must not be promoted directly, and are closed by appending `[Handoff:done]` — never by deleting history.
  - Log verified durable insights to today's log (`.memories/YYYY-MM-DD.md` locally or `memories/` globally) as `[Candidate]` entries **with a daily time stamp** (e.g., `[HH:MM]`).
- [ ] **3. Promotion & Long-Term Prune (Interactive)** — delegate to **`/mem-promote`**:
  - Scan daily logs for `[Candidate]` facts and propose promotion; scan durable files
    for duplicates/obsoletes. Perform the interactive edits under `/mem-promote`.
- [ ] **4. Cross-Device Git Sync (Daily Flow)** — delegate to **`/mem-sync`**:
  - Run `mem-sync-git.sh pull` at session start and `push` at session end or after promotion.
  - The script lives at `skills/mem-sync/scripts/mem-sync-git.sh`; see that skill for details.
- [ ] **5. Short-Term Cleanup & Cloud Conflicts (Interactive)** — delegate to **`/mem-clean`**:
  - When expired daily logs (older than the 30-day retention) or cloud conflict copies
    exist, point the user to `/mem-clean`. Do not delete or rewrite history here.
- [ ] **6. Handoff Closure**:
  - **Read [references/session-handoff.md](references/session-handoff.md)** for closure guidelines.
  - When a task is fully achieved and verified, append a `[Handoff:done]` entry referencing the task so future sessions skip the resolved handoff. Do not delete prior `[Handoff]` history — the dated log is pruned on its own schedule and synced append-only across devices.
