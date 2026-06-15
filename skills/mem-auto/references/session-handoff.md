# Session Handoff

Use a `[Handoff]` file to transfer active task state across sessions. Each active task
gets its own file, kept separate from the date-anchored `[Candidate]` daily logs because
its lifetime follows the task, not the calendar.

`[Handoff]` state is transient active state, not durable memory. It must not be promoted
directly; durable insights belong in `[Candidate]` notes. A handoff is closed by deleting
its file, not by accumulating a step-by-step journal.

## Location & naming

One file per active task under the project memory directory:

```
.memories/handoffs/YYYY-MM-DD__<slug>.md
```

- `YYYY-MM-DD` is the creation day (for ordering and recognition).
- `<slug>` is an agent-chosen short name fitting the current task context.
- The `handoffs/` subdirectory syncs across devices through `/mem-sync` along with the
  daily logs.

## Format

The file's location under `.memories/handoffs/` already identifies it as a handoff — no
`[Handoff]` marker or fixed heading is needed inside. Use whatever Markdown structure best
fits the task; the sections below are a suggested shape, not a required template. Drop the
ones that do not apply.

```markdown
# <short task name>

## Goal
The ultimate objective and the immediate sub-goals.

## Progress
What is implemented so far; files edited or created; key decisions.

## Verification
Tests passed, compilers run, pre-existing failures.

## Next Actions
Clear, step-by-step actions the next agent should execute immediately.

## Blockers & Assumptions
Current obstacles or unverified assumptions.

## Suggested Skills
The next relevant skills or workflows to invoke, if any.
```

Keep it a single live delta: include only facts a fresh agent would need to continue, and
**update the file in place** as the task progresses rather than appending new blocks.
Reference existing artifacts by path or URL instead of duplicating code, logs,
screenshots, or long command output. Several tasks may each have their own open handoff
file; resume by listing `.memories/handoffs/` and picking the relevant one.

## Closure

Once the task is fully achieved and verified, **delete its handoff file**. Completion
removes the transient state; nothing about it needs to persist, because any durable
insight should already be captured as a `[Candidate]` note.
