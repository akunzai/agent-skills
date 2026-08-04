# agent-skills Developer Guidelines

## Quick Commands
- Test All: `mise run test`
- Single Test: `bash tests/<name>.sh` (e.g., `bash tests/agents-md-content.sh`)
- Lint All: `mise run lint`
- Lint Shell Scripts: `mise run lint-shell`
- Lint Workflows: `mise run lint-actions`

## Rich References & Specs
- Contribution Guidelines & Skill Structure Spec: @CONTRIBUTING.md
- Gold-Standard Test Spec: @tests/agents-md-content.sh

## Architecture Overview
- `/skills`: Agent skills directory (`/skills/<skill-name>/SKILL.md`)
- `/tests`: Bash automated test scripts (`tests/*.sh`)
- `.github/workflows`: CI workflows

## Workflows & Conventions
- **Skill Requirements**: Every skill lives in `skills/<name>/` and must contain `SKILL.md` with valid YAML frontmatter (`name`, `description`).
- **Skill Documentation**: When creating or updating a skill in `skills/`, always update `README.md` to document its description and link.
- **Shell Scripts**: Shell script style and linting standards are defined in @CONTRIBUTING.md.
- **Single Test Execution**: Always run a targeted single test (`bash tests/<name>.sh`) during fast iteration.
- **Knowledge Writeback**: When non-obvious gotchas or framework quirks are discovered, propose adding context-tagged rules to a `## Lessons Learned` section (create it if it doesn't already exist) upon user confirmation (keep max 5 items; prune or promote stale entries).

## Claude Code Compatibility

> [!NOTE]
> This repository maintains compatibility with Claude Code. The file `CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. 
> All commands, style guides, and workflows defined in `AGENTS.md` apply to both Antigravity (and other agentic assistants) and Claude Code.
> **DO NOT** delete the `CLAUDE.md` symbolic link or edit it independently; all guidelines must be updated directly in `AGENTS.md`.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the repository's default canonical triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Skill evaluation

The API-level response evaluation is manual-only and diagnostic; see
`docs/evals/api-paired.md`. When changing a covered skill, run the
credential-free fixture and paired-runner contract tests locally. For
real model-backed evidence, dispatch `.github/workflows/api-paired-eval.yml`
with the `skills-evals` environment-scoped secret. Spend is governed by the
OpenRouter account budget; the workflow does not add a local cost gate. It is
not a pull-request or release gate.
