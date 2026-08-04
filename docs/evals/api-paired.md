# API Paired Runner

evals/run-api-paired.sh is the repository-owned one-turn adapter for the
OpenRouter API evaluation lane. It consumes the validated profile from #84 and
emits one matched treatment/control pair for every target model.

For each target, the runner sends exactly two non-streaming
POST /chat/completions requests:

- treatment receives the task plus one selected skill in a controlled
  SKILL-CONTEXT message.
- control receives the identical task and request settings without that
  selected skill.

The target model, OpenRouter provider routing, fixture revision, task hash, and
skill hash are recorded on each pair. The runner records the provider-reported
resolved model when available, but it does not score responses or aggregate
models. judge_model is preserved for the later judge slice; this runner does
not call the judge.

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
treatment/control pairing, skill isolation, model propagation,
one-request-per-condition behavior, provider routing, typed failures, and
redaction. No response body, stderr, or authorization header is written to the
durable result.

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
environment. Validate the pinned response-level fixture, prepare a profile,
and use its checked-in task and skill inputs:

    bash tests/api-fixtures.sh

    evals/api-evaluation-profile.sh \
      --target-models 'openai/eval-target,x-ai/eval-target' \
      --judge-model 'anthropic/eval-judge' \
      --output "$RUNNER_TEMP/api-profile.json"

    export OPENROUTER_API_KEY
    evals/run-api-paired.sh \
      --profile "$RUNNER_TEMP/api-profile.json" \
      --task-file evals/fixtures/api/agents-md/representative-task/task.txt \
      --skill-file skills/agents-md/SKILL.md \
      --skill-name agents-md \
      --fixture-revision agents-md-api-v1 \
      --artifact-dir "$RUNNER_TEMP/api-paired"

The runner does not yet load the rubric or score responses; that belongs to
the later judge slice. It also does not retry, follow up, resume a session, or
silently substitute a model. Missing credentials and provider-side failures produce
status: failed, outcome: not-scored, and a typed error code; they are never
treated as task passes. Common codes include credential_missing,
credentials_rejected, model_unavailable, provider_rate_limited, provider_error,
request_timeout, provider_transport_error, and response_malformed.
