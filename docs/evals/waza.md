# Waza evaluation

Suites under `evals/<skill>/` measure those skills on **GitHub Copilot
only**, using the pinned catalog id in each `eval.yaml` `config.model`.
The three worker-routing suites use `gemini-3.8-flash`; the remaining suites
use their own pinned model. Skills remain usable in other assistants; those
runtimes are not the effectiveness instrument.

Covered: `agents-md`, `mise`, `aube`, `tidy-commits`, `to-memory`,
`backfill-unit-tests`, `pr-workflow`, `write-e2e-tests`, `github-epic`,
`gitlab-epic`, `to-walkthrough-video`, `setup-agent-ready-repo`.
Not covered here: `agentsview-extract`, `agentsview-resume` — a suite
would need a populated AgentsView archive, not just the CLI. Their
cited CLI surface is checked by `tests/agentsview-cli-contract.sh`
(`mise run test-agentsview-contract`) instead.

## Install

Project-level via mise's `github:` backend. Pin the CLI tag
(`v0.38.7`). GitHub's `/releases/latest` is the `azd-ext-*` release,
and `version = "latest"` with `version_prefix = "v"` currently
resolves to no versions.

```bash
mise install
waza --version
```

```bash
# Every suite
mise run waza

# One suite (or several)
mise run waza -- pr-workflow
mise run waza -- github-epic gitlab-epic

# Suites touched vs origin/main
mise run waza -- --changed

# Local iteration without Copilot when the spec is unchanged
waza run evals/pr-workflow/eval.yaml --cache
```

`waza run --cache` writes `.waza-cache/` (gitignored). It skips a task
when the eval spec, tasks, and fixtures are unchanged. Do not treat a
cache hit as a substitute for a live CI run after a skill edit.

## Auth

- Local: `copilot login`
- CI: `GITHUB_TOKEN` plus workflow permission `copilot-requests: write`

The CI job treats a run as skipped when Waza's result reports only Copilot
quota, billing, or subscription-unavailable errors. It stops the remaining
suites and preserves the error result as an artifact. Unknown auth, network,
config, model, and grader errors still fail the check, and so do rate-limit
errors — throttling is transient and must not green-light a PR. A suite whose
result file Waza never wrote fails the check too. There is no mock fallback.

The classification reads each run's `error_msg`, which is prose rather than a
code: Waza stores the SDK error string, and the SDK renders a session error as
`session error: <human message>`, dropping the structured `errorCode` /
`errorType`. `evals/run-suites.sh` therefore matches the human wording and
keeps the CAPI quota codes only as belt-and-braces.

## CI green vs effectiveness

PR check success means every `waza run` suite's graders passed (exit
0). That is not the `--baseline` improvement.

The merge gate is `mise run waza` from Install above; the PR job narrows it
to `--changed`.

```bash
# Effectiveness (local, or workflow_dispatch with baseline=true)
waza run evals/agents-md/eval.yaml --baseline
```

`--baseline` runs each task twice (no skill, then with skill) and
reports Waza improvement: quality / tokens / turns / time / completion.
The PR job does not pass `--baseline` unless dispatched with
`baseline=true`.

### Worker-routing coverage

The `backfill-unit-tests`, `pr-workflow`, and `tidy-commits` suites verify the
caller-visible routing decision tree: cheapest-capable model, lowest sufficient
effort, named-to-generic fallback, permission preservation, and truthful runtime
metadata reporting. They do not prove that Copilot launched a subagent or
honored a requested model or effort. That requires a separate integration seam
which asserts Copilot `subagent.started`/`subagent.completed` event metadata;
final-answer text and worker self-report are not evidence of actual routing.

### What a document grader may assert

`evals/setup-agent-ready-repo/graders/documents.sh` grades files the skill
writes into the workspace, and their wording is the author's, not the skill's.
The line it has to hold:

- **Assert what the skill or its templates pin**, and assert it directly. The
  documents being English throughout is a Phase 1 rule, so the grader tests for
  stray CJK rather than inferring the language from whether the English word
  `exempt` survived further down the file. A proxy assertion fails for the right
  reason only by luck, and names the wrong defect when it does.
- **Assert a section's existence, not its prose.** That a diagram table, an
  exempt-paths list, or a `drift:` marker another script parses is present is
  pinned by `references/templates/`; the sentences around them are not.
- **Report every failing assertion, then exit once.** Fail-fast made one defect
  — documents translated into the ticket language — surface as a different
  single message per run, which read as four unrelated flaky assertions and hid
  that the suite was reporting a real skill bug (#183).

`tests/setup-agent-ready-repo-grader.sh` pins that contract offline: a compliant
workspace passes, a translated one fails naming the language rule, and a
workspace missing three guarantees reports all three. It needs no Copilot, so a
grader edit is verified before any premium request is spent.

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

The PR job runs the token check, then only the suites whose
`skills/<name>/` or `evals/<name>/` paths changed vs `origin/main`.
Changes to the workflow, `.waza.yaml`, `mise.toml`, or
`evals/run-suites.sh` run every suite. `workflow_dispatch` runs every
suite, or the one named in the `suite` input.

That mapping, plus Waza applying only suite-level `graders` (v0.38.7
ignores a task's own `graders:`), means new coverage belongs in an
existing suite's task — a second task fails the first one's graders, and
a suite not named after a skill never runs on that skill's changes.
Widen that task's own prompt, not its `follow_up_prompts`: graders read
`final_output`, which holds the last turn alone, so an earlier turn's
answer is invisible to them.

In this workflow's live probe, the GitHub Actions installation token returned
no quota snapshots from `account.getQuota`. The workflow therefore classifies
Waza's runtime result instead of relying on a quota preflight. Revisit
preflight detection when GitHub exposes installation quota or billing
availability.

```bash
waza tokens compare origin/main --skills --threshold 10 --strict
bash evals/run-suites.sh --changed
```

`--strict` uses the absolute `SKILL.md` budget in
[`.waza.yaml`](../../.waza.yaml) (3000). `--threshold 10` still fails a
SKILL.md that grows more than 10% vs `origin/main`.

Exit 1 (grader failure) or 2 (config / auth / runtime error) fails the
check, except for the Copilot-unavailable case above, which
`evals/run-suites.sh` converts to a warning and exit 0.

## Workspace

Tasks run in an isolated Waza workspace. Graders do not verify a
mutation outside that workspace.
