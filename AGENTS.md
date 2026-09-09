# agent-skills Developer Guidelines

This is a repository of reusable agent skills (Memory, Git, Toolchain, Testing,
Media).

This project uses mise for the toolchain and task runner.

## Pointers

- Skill structure, shell style, plugin versions: @CONTRIBUTING.md
- Gold-standard test spec: @tests/to-memory-storage.sh
- Skill catalog (`README.md` + `skills/`): @tests/skill-catalog-sync.sh
- Issue tracker: @docs/agents/issue-tracker.md
- Pull requests: @docs/agents/pull-request.md
- Verification: @docs/agents/verification.md
- Triage labels: @docs/agents/triage-labels.md
- Domain docs: @docs/agents/domain.md
- Copilot CLI plugin compatibility: @docs/agents/copilot-cli.md
- When changing a covered skill: @docs/evals/waza.md (live Copilot eval via
  `.github/workflows/waza-eval.yml`)

## Prevent Recurrence

- **Candidate**: Name who hits this again, in which file, on what change. No such scenario, nothing to propose.
- **Promote**: Offer the first tier that reaches them and only that one, pending confirmation — enforce it (assert/type/test) with its size quoted, else a comment at that site, else an agent-facing doc (merge an existing topic doc, else `docs/agents/<topic>.md`, else `docs/agents/lessons-learned.md`) with one `@path` line under Pointers and one sentence on why the tiers above cannot hold it.
- **Prune**: When adding to a file, audit the rest of it in the same pass. Drop entries once stale (obsolete version, now enforced, duplicated, or a transcript) — not by a fixed count.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
