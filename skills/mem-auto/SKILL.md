---
name: mem-auto
description: Memory autopilot for open [Handoff] resume/closure, verified [Candidate] capture, and delegation to /mem-recall, /mem-promote, /mem-clean, and /mem-sync.
---

# mem-auto — Unified Memory Autopilot

Runs the automatic memory loop; delegate detailed work to the narrow mem-* skills.

## Memory Scopes

- Long-term memory: global durable preferences in `~/.agents/MEMORY.md`; project durable rules in `AGENTS.md` or `CLAUDE.md`.
- Short-term memory: daily `[Candidate]` logs in `~/.agents/memories/YYYY-MM-DD.md`; project `.memories/YYYY-MM-DD.md` also stores `[Handoff]` and syncs through `/mem-sync`.

## Delegation

Use `/mem-recall` for short-term lookups, `/mem-promote` for durable promotion/prune,
`/mem-clean` for destructive cleanup, and `/mem-sync` for project log status/diff/pull/push.

## Autopilot Loop

- [ ] **Start / Handoff In**
  - In cross-device projects, run `/mem-sync` pull first.
  - Scan `.memories/YYYY-MM-DD.md` for the newest `[Handoff]` with no later `[Handoff:done]`; if several are open, list them and let the user pick.
  - If the handoff is stale or its branch is merged/gone, ask before resuming.
  - Treat auto-loaded `AGENTS.md` / `CLAUDE.md` as the normal source for durable instructions; use `/mem-recall` for short-term logs, and inspect durable files only when their loaded content seems incomplete or exact wording matters.
- [ ] **Capture**
  - Before writing task state, apply [references/security.md](references/security.md) and [references/session-handoff.md](references/session-handoff.md).
  - At milestones, blockers, quota/context limits, or session boundaries, append a `[Handoff]` handoff delta: only what a fresh agent would need to continue, including goal, progress, verification, next actions, blockers/assumptions, and suggested skills.
  - Reference existing artifacts by path or URL instead of duplicating contents.
  - Treat `[Handoff]` as transient active state: not a `[Candidate]`, not promotable directly, and closed only by appending `[Handoff:done]`.
  - Log verified durable insights to today's log (`.memories/YYYY-MM-DD.md` locally or `memories/` globally) as `[Candidate]` entries **with a daily time stamp** (e.g., `[HH:MM]`).
- [ ] **Sync**
  - Use `/mem-sync` for project daily-log Git operations. Its `mem-sync-git.sh status` and `diff` commands are read-only checks for local/remote `.memories/` differences.
  - Pull before reading remote handoffs; push at session end or after promotion/capture changes that should be available on other devices.
- [ ] **Manual Governance**
  - Delegate promotion/prune to `/mem-promote`; delegate expired logs and conflict copies to `/mem-clean`. Do not delete or rewrite history from `mem-auto`.
- [ ] **Closure**
  - When the task is achieved and verified, append `[Handoff:done]` for that task. Do not delete prior `[Handoff]` history.
