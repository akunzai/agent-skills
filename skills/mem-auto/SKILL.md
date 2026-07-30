---
name: mem-auto
description: Run the automatic memory lifecycle on mem-auto, /mem-auto, or $mem-auto — capture verified [Candidate] notes to global project memory, and delegate to mem-recall, mem-promote, and mem-clean.
metadata:
  related-skills: mem-recall, mem-promote, mem-clean, mem-sync
---

# mem-auto — Unified Memory Autopilot

Runs the automatic memory loop; delegate detailed work to the narrow mem-* skills.

## Memory Scopes

- Long-term memory: global durable instructions, preferences, facts, and reusable conventions in `~/.agents/AGENTS.md` (the canonical core read natively by every agent); project durable rules in `AGENTS.md` or `CLAUDE.md`.
- Short-term memory: daily `[Candidate]` logs in `~/.agents/memories/YYYY-MM-DD.md` (global) and `~/.agents/memories/projects/<proj-slug>/YYYY-MM-DD.md` (project-specific, resolved via `skills/mem-auto/scripts/resolve-proj-memory-path.sh`). Session handoffs are handled by dedicated handoff skills.

## Delegation

Use `/mem-recall` for short-term lookups, `/mem-promote` for durable promotion/prune,
and `/mem-clean` for destructive cleanup.

## Autopilot Loop

- [ ] **Start / Path Resolution**
  - Resolve the project's global short-term memory path by executing `skills/mem-auto/scripts/resolve-proj-memory-path.sh` (or `skills/mem-auto/scripts/ensure-proj-memory-path.sh` to also execute `skills/mem-auto/scripts/migrate-legacy-proj-memory.sh` for legacy `<repo>/.memories/` migration and ensure directory creation). This returns `~/.agents/memories/projects/<proj-slug>/`.
  - Treat auto-loaded `AGENTS.md` / `CLAUDE.md` as the normal source for durable instructions; use `/mem-recall` for short-term logs, and inspect durable files only when their loaded content seems incomplete or exact wording matters.
- [ ] **Capture**
  - Before writing task state, apply [references/security.md](references/security.md).
  - **Capture gate — write only if it passes.** Ask: would a fresh agent be wrong, blocked, or materially slower without this note? If not, write nothing. Capturing nothing is a valid and common outcome; never log just to fill the step.
  - **Never capture (avoids running-log noise):** routine successful steps, restatements of the task or request, or anything already recoverable from code, tests, `git log`, docs, or external trackers (e.g., GitHub/GitLab Issues). If a suitable external tracker is available, ask the user whether to open an issue instead of logging it.
  - Log verified durable insights to today's log (`~/.agents/memories/projects/<proj-slug>/YYYY-MM-DD.md` or `~/.agents/memories/YYYY-MM-DD.md` globally) as `[Candidate]` entries **with a daily time stamp** (e.g., `[HH:MM]`). A `[Candidate]` must generalize beyond the current task — good: a reusable convention, a non-obvious environment constraint, a gotcha that will recur; bad: one-off task progress or a past fix.
  - Session handoffs are decoupled from `mem-auto`; use dedicated handoff skills when task suspension or handoff notes are required.
- [ ] **Manual Governance**
  - Delegate promotion/prune to `/mem-promote`; delegate expired logs and conflict copies to `/mem-clean`. Do not delete or rewrite history from `mem-auto`.

