# Contributing

Thank you for your interest in contributing to **agent-skills**! This guide
will help you get started.

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting Issues

- **Bugs** — open a [Bug Report](https://github.com/akunzai/agent-skills/issues/new?template=bug_report.yml).
- **Feature requests** — open a [Feature Request](https://github.com/akunzai/agent-skills/issues/new?template=feature_request.yml).
- **Security vulnerabilities** — see [SECURITY.md](SECURITY.md). Do **not**
  open a public issue.

## Development Setup

This project uses [mise](https://mise.jdx.dev/) to manage development tools
(ShellCheck, actionlint, uv, jq) and tasks. After
[installing mise](https://mise.jdx.dev/getting-started.html):

```bash
git clone https://github.com/akunzai/agent-skills.git
cd agent-skills

# Install the pinned tools declared in mise.toml
mise install

# Run all tests
mise run test

# Lint shell scripts and workflows
mise run lint
```

### Prerequisites

| Tool | Purpose |
| --- | --- |
| [mise](https://mise.jdx.dev/) | Provisions the tools below and runs tasks |
| Bash 4+ | Tests and hook scripts |
| [ShellCheck](https://www.shellcheck.net/) | Shell linting (`mise run lint-shell`) |
| [actionlint](https://github.com/rhysd/actionlint) | GitHub Actions linting (`mise run lint-actions`) |
| [zizmor](https://github.com/zizmorcore/zizmor) | GitHub Actions security linting (`mise run lint-workflows`) |
| [waza](https://github.com/microsoft/waza) | Skill spec + eval schema (`mise run lint-skills`) |
| [agentsview](https://github.com/kenn-io/agentsview) | CLI surface the `agentsview-*` skills cite (`mise run test-agentsview-contract`) |
| [SkillSpector](https://github.com/NVIDIA/SkillSpector) | Static security scan of every published skill and plugin (`mise run lint-skill-security`) |

To accept a new SkillSpector finding as a false positive or already-documented
behaviour, add an entry with a one-line reason to `.skillspector-baseline.yaml`
(a genuine issue gets fixed instead, not suppressed) and re-run
`mise run lint-skill-security` to confirm it is clear.

## Writing a Skill

Each skill lives in `skills/<name>/` and must contain at least a `SKILL.md`.

```text
skills/<name>/
├── SKILL.md            # Required — main instructions
├── scripts/            # Optional — helper shell scripts
├── references/         # Optional — supplementary docs
└── examples/           # Optional — usage examples
```

### SKILL.md Requirements

The file must start with YAML frontmatter:

```yaml
---
name: my-skill
description: >-
  One-line description of when and how to use this skill.
metadata:
  capabilities: shell, network
---
```

`metadata.capabilities` is required: a comma-separated list of what the
skill can make the agent do, drawn from the vocabulary in
[SECURITY.md](SECURITY.md#capabilities), or `none` alone. Derive it from
the `SKILL.md`, references, and scripts, not the skill's name.
`tests/skill-capabilities.sh` enforces it. Do not use `allowed-tools`; it
pre-approves tools rather than restricting them.

Write `SKILL.md` in **English**, including `description`. Agents follow
the file; English is the shared language across harnesses.

Also add `./skills/<name>` to the `skills` array in
`.claude-plugin/plugin.json` so `skills add` / `npx skills add` groups it under
**Charley Skills**.

### Manual-only skills

A skill with side effects, or one only the user should trigger by name
(never inferred from conversation), needs both (runtimes differ in which
one they honour; see `docs/agents/harnesses.md`):

- `disable-model-invocation: true` in `SKILL.md` frontmatter. Keep the
  `description` human-facing (a one-line summary) and drop trigger-phrase
  lists ("Use when the user says…"), since the model no longer auto-matches
  on it.
- `agents/openai.yaml` beside `SKILL.md`, with
  `policy.allow_implicit_invocation: false` and
  `interface.display_name`/`short_description`.

```yaml
# agents/openai.yaml
interface:
  display_name: "My Skill"
  short_description: "One-line summary"
policy:
  allow_implicit_invocation: false
```

### Adding Tests

Do not add grep-the-SKILL.md phrase locks. Skill structure is
`mise run lint-skills` (`waza check`); behavior is a Waza suite under
`evals/<name>/`. For helper scripts, add a test that actually runs the
script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ... invoke the script, assert exit codes and outputs
```

Register the test in `.github/workflows/tests.yml` under an appropriate job.

## Plugin versions

Installed plugins update only when the manifest `version` string changes;
which runtime keys updates on which manifest is in `docs/agents/harnesses.md`.
When shipped files under `plugins/<name>/` change, bump `version` in both
`plugins/<name>/.claude-plugin/plugin.json` and
`plugins/<name>/.codex-plugin/plugin.json` and keep them equal. Patch for
text or script fixes, minor for new roles or contracts, major for breaking
role names or permission boundaries. `tests/plugin-version-bump.sh`
enforces the bump. The repository-root lifecycle manager copies Codex personal
agents as a plugin post-action, so run root `scripts/upgrade.sh` after a
release.

Catalog skills under `skills/` are not plugins. Do not add them to
`.claude-plugin/marketplace.json` or `.agents/plugins/marketplace.json`.
Every marketplace plugin lives under `plugins/<name>/` and needs an entry in
both marketplace files. Root `.claude-plugin/plugin.json` is only the
`skills add` / `npx skills add` catalog (name kebab-cases to **Charley
Skills**); it has no `version` and is not installable as a plugin.

## Catalog releases

Catalog skills under `skills/` share one repository version, a semver tag
`vMAJOR.MINOR.PATCH`. Installers track the branch by content hash, not by
tag, so a release exists for readers: pushing a tag that points at `main`
runs `.github/workflows/release.yml`, which publishes a GitHub Release with
notes grouped by pull-request label. `.github/workflows/pr-labeler.yml`
derives that label from the branch prefix (`feat/`, `fix/`, `docs/`, `ci/`,
`refactor/`, `test/`, `chore/`) and adds `breaking` when the title carries a
Conventional Commit `!`.

- **Major**: a skill is renamed or removed, loses a trigger, or changes where
  or how it stores data — anything an installed user must act on. Add a
  README migration note with the exact commands, and declare the old name
  with `metadata.replaces` in the renamed skill's frontmatter.
- **Minor**: a new skill, or a new capability or trigger in an existing one.
- **Patch**: fixes, wording, tests, and evals.

```bash
git tag v1.2.0 origin/main && git push origin v1.2.0
```

## Code Style

- All shell scripts must pass **ShellCheck** with no warnings.
- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Indent with **2 spaces** (no tabs).
- Keep lines reasonable in length.

## Pull Request Process

1. Fork the repository and create a feature branch.
2. Make your changes with clear, focused commits.
3. Ensure `mise run test` and `mise run lint` pass.
4. Open a PR against `main`.
5. Describe what changed and link any related issues.
