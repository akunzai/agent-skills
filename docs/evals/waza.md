# Waza evaluation

Suites under `evals/<skill>/` measure those skills on **GitHub Copilot
only**, using the pinned catalog id in each `eval.yaml` `config.model`
(`mai-code-1.1-flash`). Skills remain usable in other assistants;
those runtimes are not the effectiveness instrument.

Covered: `agents-md`, `mise`, `aube`, `tidy-commits`, `to-memory`,
`backfill-unit-tests`, `pr-workflow`, `write-e2e-tests`, `github-epic`,
`gitlab-epic`.
Not covered here (needs AgentsView): `agentsview-extract`.

## Install

Project-level via mise's `github:` backend. `version_prefix = "v"` so
`latest` resolves to CLI tags (`v0.38.6`) instead of `azd-ext-*`
releases.

```bash
mise install
waza --version
```

Or `mise run waza` to run every suite.

## Auth

- Local: `copilot login`
- CI: `GITHUB_TOKEN` plus workflow permission `copilot-requests: write`

Unauthenticated Copilot fails the run. There is no mock fallback.

## CI green vs effectiveness

PR check success means every `waza run` suite's graders passed (exit
0). That is not the `--baseline` improvement.

```bash
# Merge gate (same loop as the PR job)
waza run evals/agents-md/eval.yaml
waza run evals/mise/eval.yaml
waza run evals/aube/eval.yaml
waza run evals/tidy-commits/eval.yaml
waza run evals/to-memory/eval.yaml
waza run evals/backfill-unit-tests/eval.yaml
waza run evals/pr-workflow/eval.yaml
waza run evals/write-e2e-tests/eval.yaml
waza run evals/github-epic/eval.yaml
waza run evals/gitlab-epic/eval.yaml

# Effectiveness (local, or workflow_dispatch with baseline=true)
waza run evals/agents-md/eval.yaml --baseline
```

`--baseline` runs each task twice (no skill, then with skill) and
reports Waza improvement: quality / tokens / turns / time / completion.
The PR job does not pass `--baseline` unless dispatched with
`baseline=true`.

## Spec (replaces `skills-ref validate`)

`waza check --format json` covers the agentskills.io frontmatter spec,
eval YAML schema, and link checks. The process always exits 0, so
`mise run lint-skills` (`tests/waza-spec.sh`) fails only when a spec
check, schema, or link has `passed: false`. It ignores Waza's
compliance score (`USE FOR:` / `DO NOT USE FOR:`) and advisory
style notes.

[`.github/workflows/validate-skills.yml`](../../.github/workflows/validate-skills.yml)
runs that task on every PR. It does not need Copilot.

## CI

[`.github/workflows/waza-eval.yml`](../../.github/workflows/waza-eval.yml)
runs on first-party PRs that touch `skills/**`, `evals/**`, the
workflow file, `.waza.yaml`, or `mise.toml`. Fork PRs are skipped.

The PR job runs:

```bash
waza tokens compare origin/main --skills --threshold 10 --strict
waza run evals/<skill>/eval.yaml --output waza-results/<skill>.json
```

for every `evals/*/eval.yaml`. `--strict` uses the absolute `SKILL.md`
budget in [`.waza.yaml`](../../.waza.yaml) (3000). `--threshold 10`
still fails a SKILL.md that grows more than 10% vs `origin/main`.

Exit 1 (grader failure) or 2 (config / auth / runtime error) fails the
check.

## Workspace

Tasks run in an isolated Waza workspace. Graders do not verify a
mutation outside that workspace.
