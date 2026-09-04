# agent-skills Developer Guidelines

This is a repository of reusable agent skills (Memory, Git, Toolchain, Testing)
for AI coding assistants.

This project uses mise for the toolchain and task runner.

## Commands

- Test one file: `bash tests/<name>.sh` (e.g. `bash tests/to-memory-storage.sh`)

Tasks live in `mise.toml` (`mise run test`, `mise run lint`).

## Pointers

- Skill structure, shell style, plugin versions: @CONTRIBUTING.md
- Gold-standard test spec: @tests/to-memory-storage.sh
- Skill catalog (`README.md` + `skills/`): @tests/skill-catalog-sync.sh
- Issue tracker: @docs/agents/issue-tracker.md
- Triage labels: @docs/agents/triage-labels.md
- Domain docs: @docs/agents/domain.md
- Copilot CLI plugin compatibility: @docs/agents/copilot-cli.md
- When changing a covered skill: @docs/evals/waza.md (live Copilot eval via
  `.github/workflows/waza-eval.yml`)

## Self-Reflection

- **Candidate**: Distill a non-obvious gotcha into ≤ 2 context-tagged bullets. Propose it before writing.
- **Promote**: On confirmation, put it where whoever would break it must already pass — enforce it (assert/type/test) when the fix is in hand, else a comment at that site, else an agent-facing doc (merge an existing topic doc, else `docs/agents/<topic>.md`, else `docs/agents/lessons-learned.md`) with one `@path` line under Pointers. Never both.
- **Prune**: Drop entries once stale (obsolete version, now enforced, duplicated, or a transcript) — not by a fixed count.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
