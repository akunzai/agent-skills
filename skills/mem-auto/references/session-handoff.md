# Session Handoff

Use `[Handoff]` entries in daily logs to transfer active task state across sessions.

`[Handoff]` entries are transient active state, not durable memory. They live beside
`[Candidate]` entries, must not be promoted directly, and close by appending
`[Handoff:done]`, not by deleting history.

## Format

Append active state to today's `.memories/YYYY-MM-DD.md` as a `[Handoff]` block:

```markdown
### [Handoff 14:05] <short task name>
- **Goal**: The ultimate objective and the immediate sub-goals.
- **Progress**: What is implemented so far; files edited or created; key decisions.
- **Verification**: Tests passed, compilers run, pre-existing failures.
- **Next Actions**: Clear, step-by-step actions the next agent should execute immediately.
- **Blockers & Assumptions**: Current obstacles or unverified assumptions.
- **Suggested Skills**: The next relevant skills or workflows to invoke, if any.
```

Keep it a handoff delta: include only facts a fresh agent would need to continue.
Reference existing artifacts by path or URL instead of duplicating code, logs,
screenshots, or long command output. Multiple tasks can each have an open handoff; the
newest open block for a task is current.

## Closure

Once the task is fully achieved and verified:
1. Append `[Handoff:done HH:MM] <task name>` so future sessions skip it.
2. Never delete prior `[Handoff]` history.
