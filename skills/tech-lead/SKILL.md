---
name: tech-lead
description: >-
  Tech-lead: split implementation into slices, brief a subagent, isolate
  independent slices in git worktrees, and accept the result in the
  primary session. Use when delegating implementation to subagents
  or running parallel worktrees.
---

# Tech Lead

You are the **tech-lead**. Implementers write code. You write the brief, isolate work, and accept.

Stay in the primary session for a few-line or single-file mechanical edit, and for architecture decisions. Delegate when the change is larger. Bounded investigation (search, facts, caller-selected checks) uses the platform's cheap named workers when those roles exist. On Cursor CLI, keep caller-selected checks in primary, since Cursor gives `check-runner` unrestricted tools (`docs/agents/cursor-cli.md`).

## 1. Slice

Split the work into units that can finish without each other's uncommitted files. For every pair that shares a path, record whether the overlap is semantic (same meaning) or mechanical (lockfile regeneration).

**Done** when each slice has a name, the files it may touch, and a parallel or serial mark. Parallel only when no pair shares semantic files.

## 2. Live capability

From this turn's system prompt and tool schemas, pick for each slice:

- the cheapest model and effort the harness exposes that can finish that slice
- an implementer role from the live list (general-purpose or equivalent)

Omitting a model parameter inherits the session model. Do that only for high-judgment slices. Mechanical slices get an explicit cheaper pick from the live list.

**Done** when every slice names a live role and either an explicit model/effort or an explicit inherit.

## 3. Implementation skills

From skills this session can already see (harness skill list, or `skills ls --json` when that CLI is present), pick 0–N whose descriptions match the slice and that teach how to implement (tests, toolchain, domain procedure). Review and audit skills wait for step 6.

Put absolute `SKILL.md` paths in the brief. That list is the full set the implementer reads.

**Done** when the brief lists those paths, or lists none.

## 4. Isolate

Prefer the harness native worktree or cwd isolation. If the harness has none, `git worktree add` beside the repo or in the harness default directory, named after the slice.

You create, collect, and remove worktrees. Each implementer receives one existing path.

**Done** when each in-flight slice has a worktree path and a branch.

## 5. Brief and dispatch

One implementer per slice. Launch parallel only for slices marked parallel in step 1.

The brief is the slice: scope, allowed files, constraints, acceptance, skill paths from step 3, worktree and branch, and when to stop and return. The implementer may commit in its worktree.

**Done** when each dispatched slice has a live handle and its brief travelled with that dispatch.

## 6. Accept

On return, record every item:

- brief constraints held
- claimed verification actually ran
- ship, ask the user, or resume the same implementer with findings

When the slice is high-risk, you invoke an installed review skill (code review, over-engineering review, security) as coordinator, after the implementer returns.

When a review artifact exists, read its findings and summary. Open the diff only if that artifact is empty or failed, the slice is high-risk, or a finding needs your ruling. Axes that review already completed stay closed.

**Done** when every slice is accepted or parked with a recorded reason.

## 7. Integrate

You push, open the MR/PR, merge, and remove the worktree. Confirm with the user first when the project requires it.

**Done** when accepted commits are on the intended branch or MR, or you recorded why not.
