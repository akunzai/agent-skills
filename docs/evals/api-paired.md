# API Paired Runner

evals/run-api-paired.sh is the repository-owned one-turn adapter for the
OpenRouter API evaluation lane. It consumes the validated profile from #84 and
emits one matched treatment/control pair for every target model and scores each
candidate with one fixed blind judge model.

For each target, the runner sends up to four non-streaming
POST /chat/completions requests:

- treatment receives the task plus one selected skill in a controlled
  SKILL-CONTEXT message.
- control receives the identical task and request settings without that
  selected skill.
- the fixed judge receives the task, rubric, and one candidate response at a
  time, without target model identity, condition labels, or the other response.

The target model, fixed independent judge model, OpenRouter provider routing, fixture
revisions, hashes, request metadata, timing, and permitted usage/cost fields
are recorded on each pair. Candidate content and raw judge output are never
written to the durable artifact. The runner computes a treatment-minus-control
lift independently for each target and emits no tiers, groups, rankings, or
aggregate score.

## Method references adopted

The runner adopts two narrow ideas from native evaluation harnesses such as
[`superpowers-evals`](https://github.com/prime-radiant-inc/superpowers-evals/):

- deterministic evidence remains separate from later LLM judging; malformed,
  incomplete, or infrastructure-invalid runs are typed as not-scored rather
  than converted into task failures or passes;
- each pair carries enough bounded fixture, skill, task, model-routing, and
  request metadata to reproduce the comparison without retaining raw provider
  transcripts.

Those ideas do not expand this lane into a native-runtime evaluation. The MVP
still evaluates one-turn response behavior only; native tool-call, transcript,
filesystem, worktree, and interactive-driver checks belong to a separate future
lane.

For a later replicate/methodology slice, candidate safeguards include a frozen
no-skill control, fixed provider/model/fixture inputs, pre-registered replicate
and decision rules, blind condition-label rotation, manual review of automated
flags, and an explicit rerun rule for infrastructure-indeterminate cells. These
are future methodology inputs, not new requirements for this MVP's one request
per condition contract.

## Local contract test

Ordinary tests do not need an OpenRouter credential or network access:

    bash tests/api-paired-runner.sh

The test injects a temporary fake curl through CURL_BIN. That transport checks
the real request shape and returns deterministic mock responses. It verifies
treatment/control pairing, skill isolation, model propagation, blind judge
inputs, bounded score parsing, per-target paired lift, deterministic findings
separate from judge findings, typed failures, and redaction. No response body,
judge transcript, stderr, or authorization header is written to the durable
result.

Response-level task and rubric fixtures live under
[`evals/fixtures/api/`](../../evals/fixtures/api/) and are validated by:

    bash tests/api-fixtures.sh

The fixture contract keeps the same task and rubric for treatment and control,
supplies one selected skill only to treatment, and pins task/skill/rubric
revisions plus hashes. The rubric describes deterministic response checks; it
does not assert native filesystem, process, permission, workspace, or tool-call
state. See [API response-level fixtures](api-fixtures.md) for the schema.

## Protected/manual run

A real run must use a protected credential and an explicitly approved
environment. The repository workflow
[`api-paired-eval.yml`](../../.github/workflows/api-paired-eval.yml) is
manual-only, uses the protected `skills-evals` environment, and is diagnostic
only; it is not a pull-request check or a release gate. The credentialed job
only runs when the manual dispatch ref is `main`; the `skills-evals` GitHub
environment must remain configured with the repository's protected secret and
approval/branch restrictions. It caps the target sweep at three models/twelve
requests, bounds the job and request timeouts, checks the reported provider
cost against the selected budget, and retains only normalized artifacts for 30
days. If any successful provider response omits its cost field, the workflow
fails closed with `cost_unreported` because the budget cannot be verified.

For local contract validation, run:

    bash tests/api-fixtures.sh

The protected workflow prepares the same profile and checked-in task/skill
inputs before the credentialed step. Its live command is equivalent to:

    evals/api-evaluation-profile.sh \
      --target-models 'openai/eval-target,x-ai/eval-target' \
      --judge-model 'anthropic/eval-judge' \
      --output "$RUNNER_TEMP/api-profile.json"

    export OPENROUTER_API_KEY
    evals/run-api-paired.sh \
      --profile "$RUNNER_TEMP/api-profile.json" \
      --task-file evals/fixtures/api/agents-md/representative-task/task.txt \
      --task-revision agents-md-task-v1 \
      --skill-file skills/agents-md/SKILL.md \
      --skill-revision agents-md-skill-v1 \
      --skill-name agents-md \
      --fixture-revision agents-md-api-v1 \
      --rubric-file evals/fixtures/api/agents-md/representative-task/rubric.json \
      --rubric-revision agents-md-micromanagement-v1 \
      --artifact-dir "$RUNNER_TEMP/api-paired"

The profile must use a judge identifier that is not present in the target sweep.
The runner requires the pinned rubric and revision metadata. Deterministic
findings are bounded response-level checks from the rubric; the judge emits an
integer score from `0` through `100` plus at most three short evidence strings.
Malformed judge JSON, invalid scores, secret-bearing evidence, missing candidate
responses, and provider failures are typed as not-scored infrastructure results.
The runner does not retry, follow up, resume a session, or silently substitute a
model. Common codes include credential_missing, credentials_rejected,
model_unavailable, provider_rate_limited, provider_error, request_timeout,
provider_transport_error, response_malformed, judge_response_malformed,
judge_score_invalid, and judge_redaction_failure.
