---
name: to-memory
description: Explicitly record something worth remembering, deciding scope (global vs. project) and tier (short-term candidate vs. long-term durable), then writing it. Use on `/to-memory`, "remember this", or `$to-memory`. Autonomous knowledge capture after solving a problem is agents-md's Self-Reflection, not this skill.
---

# to-memory — Explicit Memory Capture

Records one thing the user explicitly asked to remember.
It never runs an autonomous capture loop — that belongs to `agents-md`'s Self-Reflection.

## Scope and tier

Two independent decisions, each resolved from an explicit argument, semantic
inference from the request, or by asking when genuinely ambiguous:

- **Scope** — `global` (`~/.agents/...`, read by every agent and project) or
  `project` (this repo only).
- **Tier** — `long-term` (durable, timeless, must be explicitly requested) or
  `short-term` (dated candidate; the default when ambiguous).

## When tier is long-term

Write directly into the durable target — no intermediate staging or batch review:

- Global: `~/.agents/AGENTS.md`
- Project: `<repo>/AGENTS.md` (fallback `<repo>/CLAUDE.md` if `AGENTS.md` is absent)

Before writing, hold the note to this bar:

- **Verified** — proven to work in this workspace, not a guess.
- **Reusable** — likely useful again, not one-off task progress.
- **Stable** — a lasting convention, not a temporary hack.
- Strip time-of-day stamps (e.g. `[HH:MM]`) — durable files are timeless.
- Keep durable files lean (aim under 100 lines). If this note would push a file
  well past that, say so and offer to fold or replace an older entry instead of
  just appending.

Always show the exact addition and get explicit confirmation before writing to a
durable file.

## When tier is short-term

Land the note as its own file — one file per note, not appended to a shared log:

```text
~/.agents/memories/YYYY-MM-DD-<slug>.md                          # global
~/.agents/memories/projects/<proj-slug>/YYYY-MM-DD-<slug>.md      # project
```

- `YYYY-MM-DD` is today's date.
- `<slug>` is a short, agent-chosen topic slug, so the filename alone identifies
  the content without opening the file.
- Resolve `<proj-slug>` and the project memory directory with
  `scripts/proj-memory-path.sh` (pure resolution by default; pass `--ensure`
  to also create the directory).
- No retention policy and no resolution markers: when a note is no longer needed,
  delete the file directly — a destructive action, so get explicit confirmation
  first, same as any other destructive operation.
- To search past short-term notes, `grep`/`ls` the directories above directly — no
  dedicated recall skill is needed once you know where they live.

## Never write

Passwords, tokens, credentials, PII, or unverified speculation — see
[references/security.md](references/security.md) for the full list and how to
redact instead of dropping a note entirely.

## Cross-agent global memory setup

Wiring a newly installed coding agent's own native global memory file to
`~/.agents/AGENTS.md` is a one-time setup task, not a memory-capture action — see
[references/cross-agent-locations.md](references/cross-agent-locations.md) for the
per-agent path table. There is no dedicated script for this; wire the file by
hand, in whatever way fits its format, and back up any existing real file
first.
