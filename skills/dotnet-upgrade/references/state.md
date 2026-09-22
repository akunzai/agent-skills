# Upgrade state

The state surface holds three things: the **decisions** from Decide, the
**task list** from Plan, and a **progress log** per task. One meaning lives
in one place; never mirror the same content into two surfaces.

## Choosing the surface

1. **The repo's own convention wins.** Read the repo's agent docs for an
   issue-tracker or planning convention (`AGENTS.md` pointers,
   `docs/agents/issue-tracker.md`, or similar). If it names a surface for a
   multi-ticket effort the team must see, use it:
   - an aggregating issue (the epic) holds the milestones, the decisions
     summary, and a checklist linking one child issue per task;
   - each child issue holds its task's `Done when:` and its progress log
     as comments;
   - the repo holds only the assessment report and the ADR.
   Use the `github-epic` or `gitlab-epic` skill to create and link them.
2. **Otherwise, files in the repo** under `.upgrades/<id>/`, committed on
   the upgrade branch:

   | File | Holds |
   | --- | --- |
   | `decisions.md` | Every answer from Decide, plus later user preferences, recorded when given |
   | `assessment.md` | The project table, tiers, blockers, and the four findings |
   | `plan.md` | The task list, authoritative: `### NN-short-name`, a paragraph, `Done when:`, `trunk-safe` or `branch-only`, status |
   | `tasks/NN-short-name.md` | Append-only progress: files changed, gate commands and results, deviations |

   Task ids are stable and named by content. Delete `.upgrades/<id>/` in
   the cutover request.

Ask the user before creating an issue or any other outward-facing record.

## Where numbers are recorded

Any table of counts (projects migrated, tests passing, stubs left) states
where each number comes from (command or pipeline) and when a new row may
be added, so the rows stay comparable across sessions.

## Resume protocol

At the start of every session and after any context compaction:

1. Read the decisions, then the task list.
2. A task marked in progress is resolved first, from its progress log and
   `git log` on the branch: finish it, or record why it stopped.
3. Read the last two progress entries before starting the next task.
4. `git grep "// STUB:"` and compare against open tasks; a marker with no
   task gets one.
