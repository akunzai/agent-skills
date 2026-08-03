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

## Local contract test

Ordinary tests do not need an OpenRouter credential or network access:

    bash tests/api-paired-runner.sh

The test injects a temporary fake curl through CURL_BIN. That transport checks
the real request shape and returns deterministic mock responses. It verifies
treatment/control pairing, skill isolation, model propagation,
one-request-per-condition behavior, provider routing, typed failures, and
redaction. No response body, stderr, or authorization header is written to the
durable result.

## Protected/manual run

A real run must use a protected credential and an explicitly approved
environment. Prepare a profile and provide ordinary task and skill fixture
files:

    evals/api-evaluation-profile.sh \
      --target-models 'openai/eval-target,x-ai/eval-target' \
      --judge-model 'anthropic/eval-judge' \
      --output "$RUNNER_TEMP/api-profile.json"

    export OPENROUTER_API_KEY
    evals/run-api-paired.sh \
      --profile "$RUNNER_TEMP/api-profile.json" \
      --task-file "$RUNNER_TEMP/task.txt" \
      --skill-file skills/agents-md/SKILL.md \
      --skill-name agents-md \
      --fixture-revision agents-md-v1 \
      --artifact-dir "$RUNNER_TEMP/api-paired"

The runner does not retry, follow up, resume a session, or silently substitute
a model. Missing credentials and provider-side failures produce
status: failed, outcome: not-scored, and a typed error code; they are never
treated as task passes. Common codes include credential_missing,
credentials_rejected, model_unavailable, provider_rate_limited, provider_error,
request_timeout, provider_transport_error, and response_malformed.
