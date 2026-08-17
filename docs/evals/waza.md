# Waza evaluation

Suites under `evals/<skill>/` measure those skills on **GitHub Copilot
only**, using the pinned catalog id in each `eval.yaml` `config.model`
(`mai-code-1.1-flash`). Skills remain usable in other assistants;
those runtimes are not the effectiveness instrument.

Covered: `agents-md`, `mise`, `aube`, `tidy-commits`, `to-memory`.
Not covered here (need a forge, a browser, or AgentsView):
`github-epic`, `gitlab-epic`, `pr-workflow`, `write-e2e-tests`,
`agentsview-extract`, `backfill-unit-tests`.

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

# Effectiveness (local, or workflow_dispatch with baseline=true)
waza run evals/agents-md/eval.yaml --baseline
```

`--baseline` runs each task twice (no skill, then with skill) and
reports Waza improvement: quality / tokens / turns / time / completion.
The PR job does not pass `--baseline` unless dispatched with
`baseline=true`.

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
