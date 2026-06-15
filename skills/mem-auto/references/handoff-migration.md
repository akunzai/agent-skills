# Handoff Migration (one-time)

Earlier versions stored `[Handoff]` blocks **inside** the daily logs
(`.memories/YYYY-MM-DD.md`) and closed them by appending `[Handoff:done]`. Handoffs now
live in per-task files under `.memories/handoffs/` (see
[session-handoff.md](session-handoff.md)). Migrate once per project (and once for global
`~/.agents/memories/`) to move any old-style blocks out of the daily logs.

## When to run (at most once)

Track completion with a **sentinel file**, not the existence of `.memories/handoffs/` — a
single new per-task handoff creates that directory, which would mask un-migrated legacy
blocks still inline in older daily logs.

- **Skip** when the sentinel `.memories/.handoff-migrated` exists (global:
  `~/.agents/memories/.handoff-migrated`).
- Otherwise detect → migrate → **write the sentinel** (final step), so later sessions never
  re-scan.

Stragglers that arrive later (for example a `/mem-sync` pull of un-migrated logs from a
device that never upgraded) are surfaced on demand by `/mem-recall`'s fallback grep, which
prompts a one-off re-run — they do not justify re-checking at every start.

## Detect

```bash
# project + global daily logs that still hold legacy handoff blocks
# (dir-based grep: tolerates a missing/empty dir; modern handoffs/ files carry no
# "[Handoff" literal so they are never matched)
grep -rln "\[Handoff" .memories ~/.agents/memories 2>/dev/null
```

If grep finds nothing, there is no residue — just write the sentinel (step 6) and stop.

## Plan, then migrate

1. In cross-device projects, run `/mem-sync` pull first so migration runs on the freshest
   logs; the daily logs are git-synced, so the pre-migration state stays restorable.
2. For each task, find its **newest** `[Handoff]` block:
   - **Open** (no later `[Handoff:done]` for that task):
     - In a **project** log (`.memories/`), move it into
       `.memories/handoffs/YYYY-MM-DD__<slug>.md`, where `YYYY-MM-DD` is the block's original
       creation date and `<slug>` an agent-chosen name fitting the task. Keep only the latest
       delta — do not carry forward stacked older blocks.
     - In a **global** log (`~/.agents/memories/`) there is no handoff scope — handoffs are
       project active state. Surface the block to the user; if the task is still live,
       recreate it as a project handoff under that project's `.memories/handoffs/`, otherwise
       drop it.
   - **Closed** (`[Handoff:done]`): drop it. Completed handoffs are transient and are not
     migrated.
3. Remove the migrated/closed/dropped `[Handoff]` and `[Handoff:done]` blocks from the daily
   logs. Leave every `[Candidate]` entry untouched.
4. Present the full plan (files read, handoff files to create, blocks to strip, sentinels to
   write) and get explicit confirmation before editing daily logs, since this rewrites them.
5. After confirmation, apply the edits.
6. Write the sentinel so later sessions skip this step:
   `touch .memories/.handoff-migrated` (and `touch ~/.agents/memories/.handoff-migrated` if
   you scanned global). In cross-device setups, `/mem-sync` push so the sentinel and the
   rewritten logs travel together.
