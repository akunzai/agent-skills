# Handoff Migration (one-time)

Earlier versions stored `[Handoff]` blocks **inside** the daily logs
(`.memories/YYYY-MM-DD.md`) and closed them by appending `[Handoff:done]`. Handoffs now
live in per-task files under `.memories/handoffs/` (see
[session-handoff.md](session-handoff.md)). Run this migration once per project (and once
for global `~/.agents/memories/`) when old-style handoffs are still embedded in daily logs.

## Detect

Migration is needed when `.memories/` contains daily logs with `[Handoff]` markers and no
`.memories/handoffs/` directory yet:

```bash
grep -rln "\[Handoff" .memories/*.md 2>/dev/null
ls .memories/handoffs/ 2>/dev/null
```

## Plan, then migrate

1. In cross-device projects, run `/mem-sync` pull first so migration runs on the freshest
   logs; the daily logs are git-synced, so the pre-migration state stays restorable.
2. For each task, find its **newest** `[Handoff]` block:
   - **Open** (no later `[Handoff:done]` for that task): move it into
     `.memories/handoffs/YYYY-MM-DD__<slug>.md`, where `YYYY-MM-DD` is the block's original
     creation date and `<slug>` an agent-chosen name fitting the task. Keep only the latest
     delta — do not carry forward stacked older blocks.
   - **Closed** (`[Handoff:done]`): drop it. Completed handoffs are transient and are not
     migrated.
3. Remove the migrated/closed `[Handoff]` and `[Handoff:done]` blocks from the daily logs.
   Leave every `[Candidate]` entry untouched.
4. Present the full plan (files read, handoff files to create, blocks to strip) and get
   explicit confirmation before editing daily logs, since this rewrites them.
5. After confirmation, apply the edits, then `/mem-sync` push in cross-device setups.
