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
(ShellCheck, actionlint, uv, Python) and tasks. After
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
---
```

### Adding Tests

Create one or more test scripts in `tests/<name>-*.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ... assertions using grep, diff, etc.
# Exit non-zero on failure.
```

Register the test in `.github/workflows/tests.yml` under an appropriate job.

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
