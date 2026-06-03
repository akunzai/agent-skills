---
name: mem-promote
description: Interactively promote verified [Candidate] daily-log notes into durable long-term memory (AGENTS.md / CLAUDE.md / MEMORY.md), and prune/dedupe those long-term files. Use when reviewing candidates for promotion or consolidating durable conventions.
---

# mem-promote — Promotion & Long-Term Prune

Curates durable memory. Two related jobs, both editing long-term files only:

1. **Promote** verified `[Candidate]` notes into `AGENTS.md` (fallback `CLAUDE.md`) or
   `~/.agents/MEMORY.md` — see [references/promote.md](references/promote.md).
2. **Prune** those durable files for duplicates, obsoletes, and contradictions — see
   [references/prune.md](references/prune.md).

## Rules (summary)

- Promote only Verified + Reusable + Stable facts; exclude handoff-only transient notes.
- Strip `[HH:MM]` timestamps when promoting, to keep durable files timeless.
- On approval, mark the daily-log entry `[Promoted]`; on decline, mark it `[Rejected]`
  so short-term cleanup is not blocked by an unresolved candidate.
- Always present the exact diff/plan and get confirmation before editing durable files.
- Keep durable files lean (aim under 100 lines).
