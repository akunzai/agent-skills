# agent-skills Developer Guidelines

This is a repository of reusable agent skills (Memory, Git, Toolchain, Testing)
for AI coding assistants.

This project uses mise for the toolchain and task runner.

## Commands

- Test one file: `bash tests/<name>.sh` (e.g. `bash tests/agents-md-content.sh`)

Tasks live in `mise.toml` (`mise run test`, `mise run lint`).

## Pointers

- Skill structure and shell style: @CONTRIBUTING.md
- Gold-standard test spec: @tests/agents-md-content.sh
- Skill catalog (`README.md` + `skills.sh.json`): @tests/skill-catalog-sync.sh
- Issue tracker: @docs/agents/issue-tracker.md
- Triage labels: @docs/agents/triage-labels.md
- Domain docs: @docs/agents/domain.md
- When changing a covered skill: @docs/evals/api-paired.md (credential-free
  fixture tests locally; live run via `.github/workflows/api-paired-eval.yml`)

## Self-Reflection

- **Candidate**: Distill a non-obvious gotcha into ≤ 2 context-tagged bullets. Propose it before writing.
- **Promote**: On confirmation, write it to a dedicated file — merge an existing topic doc, else `docs/agents/<topic>.md`, else `docs/agents/lessons-learned.md`. Add or update one `@path` line under Pointers.
- **Prune**: Drop entries once stale (obsolete version, now enforced, duplicated, or a transcript) — not by a fixed count.

## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
