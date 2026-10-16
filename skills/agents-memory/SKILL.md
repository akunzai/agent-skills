---
name: agents-memory
description: >-
  Record, recall, or forget notes in the agent's global or project memory,
  deciding scope (global vs. project) and tier (short-term candidate vs.
  long-term durable) when recording. Use on `/agents-memory`,
  `$agents-memory`, "remember this", "what did I note about X", "recall",
  or "forget X". Autonomous knowledge capture after solving a problem is
  agents-md's Prevent Recurrence, not this skill.
license: MIT
metadata:
  capabilities: shell, writes-outside-repo, edits-agent-instructions
  replaces: to-memory
---

# agents-memory — Explicit Memory

Records one thing the user explicitly asked to remember, and recalls or
forgets short-term notes on request.

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
- Project: `<repo>/AGENTS.md`, where `<repo>` is the git root of the current
  working directory (the directory itself outside git) — never the directory
  this skill was loaded from.

Before writing, hold the note to this bar:

- **Verified** — proven to work in this workspace, not a guess.
- **Reusable** — likely useful again, not one-off task progress.
- **Stable** — a lasting convention, not a temporary hack.
- Strip time-of-day stamps (e.g. `[HH:MM]`) — durable files are timeless.

Placement — a root line or a topic doc behind a pointer — and the size budget
follow the `agents-md` skill.

Always show the exact addition and get explicit confirmation before writing to a
durable file.

## When tier is short-term

Land the note as its own file — one file per note, not appended to a shared log:

```text
~/.agents/memories/YYYY-MM-DD-<slug>.md                          # global
~/.agents/memories/projects/<project-name>/YYYY-MM-DD-<slug>.md   # project
```

- `YYYY-MM-DD` is today's date.
- `<slug>` is a short, agent-chosen topic slug, so the filename alone identifies
  the content without opening the file.
- Resolve `<project-name>` with `scripts/proj-memory-path.sh`;
  `--ensure` also creates the directory.
- `<project-name>` preserves the root name exactly: main repo for worktrees,
  target outside Git. Same-name projects share memory; rename to isolate.
- For project memory, check `~/.agents/memories/.project-name-migration-v1`.
  If absent, read [migration](references/project-memory-migration.md) and ask to
  copy **all projects**, mapping each `<name>-<hash6>` to its own `<name>`.
  Keep verified backups and conflicting notes; remove old directories only
  after verification. Mark completion after cleanup. Otherwise skip legacy scans.
- No retention policy or note resolution markers. Delete obsolete notes only
  after explicit confirmation.
- Recall: search these directories directly with `grep`/`ls`.

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
