# Session Handoff Specifications

This reference defines how to use `[Handoff]` entries inside the daily logs to transfer task states seamlessly across different chat sessions, developers, or agents, saving tokens and handling rate limits without context loss.

`[Handoff]` entries are transient active state, not durable memory. They live in the daily logs alongside `[Candidate]` entries, must not be promoted directly into `MEMORY.md`, `AGENTS.md`, or `CLAUDE.md`, and are closed by appending a `[Handoff:done]` entry rather than by deleting history.

## 1. Why Session Handoff?

Large language model conversations accumulate tokens rapidly. Overly long threads degrade reasoning quality and incur high token costs. By capturing the active task state at milestones or session boundaries, the current agent can hand off the work to:
- A new session of the same agent (to reset context length and save tokens).
- A different specialized agent.
- A human developer.

## 2. Handoff Entry Format

Append the active task state to today's log (`.memories/YYYY-MM-DD.md`) as a `[Handoff]` block. Multiple tasks can each have their own open `[Handoff]` block (e.g., parallel git worktrees); the newest open block for a task is its current state. Use a heading line plus a short structured body:

```markdown
### [Handoff 14:05] <short task name>
- **Goal**: The ultimate objective and the immediate sub-goals.
- **Progress**: What is implemented so far; files edited or created; key decisions.
- **Verification**: Tests passed, compilers run, pre-existing failures.
- **Next Actions**: Clear, step-by-step actions the next agent should execute immediately.
- **Blockers & Assumptions**: Current obstacles or unverified assumptions.
- **Suggested Skills**: The next relevant skills or workflows to invoke, if any.
```

Keep it a handoff delta: include only facts a fresh agent would need to continue. Reference existing artifacts by path or URL instead of duplicating code, logs, screenshots, or long command output.

## 3. The Autopilot Handoff Lifecycle

Agents must manage handoffs actively during the session lifecycle:

### A. Initialization (Handoff In)
At the very beginning of any session:
0. **Sync First**: In a cross-device setup, pull the latest daily logs first (see the git sync workflow) so you read the freshest handoff, not a stale local copy.
1. **Scan**: Search recent daily logs for the newest `[Handoff]` block that has no matching `[Handoff:done]` closure.
2. **Choose**: If several handoffs are open, list them and let the user pick which to resume.
3. **Guard Staleness**: If an open handoff is several days old or references a branch already merged/gone, ask before resuming instead of blindly continuing.
4. **Restore & Notify**: Read the chosen block as the primary context for the task and tell the user you are resuming from it.

### B. Serialization (Handoff Out)
During a session or at session boundaries:
1. **Triggers**: Append a fresh `[Handoff]` block when:
   - A major milestone or sub-task is completed.
   - The session token count is high, and you need to reset the context.
   - The model quota limit is approaching.
   - You encounter a blocker and must wait for user input.
2. **Append, don't rewrite**: Add a new `[Handoff]` block rather than editing earlier ones; the newest open block for a task wins. Do not duplicate code; reference paths and URLs instead.
3. **Separate from candidates**: `[Handoff]` blocks are not `[Candidate]` entries. If a stable convention emerges, write a separate `[Candidate]` entry after it has been verified.

### C. Closure
Once the task is fully achieved and verified:
1. **Close**: Append a `[Handoff:done HH:MM] <task name>` entry so future sessions skip the resolved handoff.
2. **Never delete**: Do not delete prior `[Handoff]` history. The dated log is pruned on its own schedule and synced append-only across devices, so a closure entry — not a deletion — is what reliably closes the handoff everywhere and keeps it from resurrecting.
