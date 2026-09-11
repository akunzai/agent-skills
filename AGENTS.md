# agent-skills Developer Guidelines

This is a repository of reusable agent skills (Memory, Git, Toolchain, Testing,
Media).

This project uses mise for the toolchain and task runner.

## Pointers

- When writing a skill or plugin, or matching shell and CI style, read `CONTRIBUTING.md`
- Gold-standard test spec: `tests/to-memory-storage.sh`
- When adding or renaming a skill, read `tests/skill-catalog-sync.sh`
- When filing or triaging an issue, read `docs/agents/issue-tracker.md`
- When opening a pull or merge request, read `docs/agents/pull-request.md`
- Before running or reporting verification, read `docs/agents/verification.md`
- When applying a triage role, read `docs/agents/triage-labels.md`
- Before exploring, read `docs/agents/domain.md`
- When changing Copilot CLI plugin loading, read `docs/agents/copilot-cli.md`
- When changing a covered skill, read `docs/evals/waza.md`

## Prevent Recurrence

- **Candidate**: Name who hits this again, in which file, on what change. No such scenario, nothing to propose.
- **Promote**: Offer the first tier that reaches them and only that one, pending confirmation — enforce it (assert/type/test) with its size quoted, else a comment at that site, else an agent-facing doc (merge an existing topic doc, else `docs/agents/<topic>.md`, else `docs/agents/lessons-learned.md`) with one backtick-path line under Pointers and one sentence on why the tiers above cannot hold it.
- **Prune**: When adding to a file, audit the rest of it in the same pass. Drop entries once stale (obsolete version, now enforced, duplicated, or a transcript) — not by a fixed count.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
