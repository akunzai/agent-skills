# Claude Full Evaluation

The Claude full evaluation is the manual release-baseline check for
`agents-md`, `tidy-commits`, and `pr-workflow`. It is never run on pushes,
pull requests, or a schedule.

## Coverage and acceptance

Each priority skill has five versioned fixtures: expected trigger, expected
non-trigger, pre-existing user changes, missing prerequisites, and a
representative task. The runner executes every case in three isolated
workspaces. A hard case is accepted when at least two replicas pass its
deterministic evidence and preservation checks; otherwise the full suite
fails.

`evals/baselines/claude-full-v1.json` is the approved, redacted summary of
the fixture identities used for comparison. Refresh it only with explicit
human approval after reviewing a successful manual run. The runner retains no
raw prompts, responses, workspaces, credentials, or authorization headers.
`results.json` records only normalized case evidence, versions, elapsed time,
and cost. GitHub Actions retains this diagnostic artifact for 30 days.
If Claude exits unsuccessfully, the runner records only a safe error category
(for example, rate limit, budget, authentication, or unknown) on the failed
replica, writes partial results with an abort reason, and stops immediately.
It also records the stderr byte count, SHA-256 fingerprint, and whether stdout
was empty, valid JSON, or invalid JSON. For valid JSON it records only the
bounded protocol fields `type`, `subtype`, and `is_error`; it never retains
raw provider stderr or response text in the artifact.

Rubric feedback belongs in a separate, non-blocking scorecard. It can guide a
reviewer but cannot change the full suite's exit status.

## Running it

Use the **Claude full evaluation** workflow from the Actions tab. It uses the
protected `skills-evals` environment and the fixed OpenRouter model identifier
`anthropic/claude-sonnet-5` by default.

The baseline profile explicitly uses Claude Code's `medium` effort and excludes
dynamic system-prompt sections so identical fixture replicas have a better
chance to reuse provider prompt caches. A run using another effort is recorded
as exploratory and cannot match the approved baseline. It does not enable response caching:
replaying a prior model response would invalidate the three-replica comparison.

Run the full suite when preparing a formal comparison, changing an approved
baseline, or upgrading Claude Code. When changing one priority skill, run its
smoke evaluation before review and link the applicable workflow run in the
pull request.
