# API Evaluation Profile

`evals/api-evaluation-profile.sh` defines the reproducible configuration seam
for the API-level skill-utility lane. It only validates and serializes
configuration; it does not make network requests or read API credentials.

The reusable/manual [`api-evaluation-profile.yml`](../../.github/workflows/api-evaluation-profile.yml)
workflow passes its `target_models` and `judge_model` inputs directly to this
profile validator. It is a configuration check only; the protected
model-backed workflow belongs to the later evaluation workflow slice.
The one-turn paired adapter that consumes this profile is documented in
api-paired.md; its ordinary contract tests use a mocked transport, while real
requests remain protected/manual.

## Defaults

The profile uses one fixed OpenRouter route and these model selections:

| Selection | Default |
| --- | --- |
| `target_models` | `openai/gpt-5.6-luna`, `x-ai/grok-4.5`, `google/gemini-3.6-flash` |
| `judge_model` | `anthropic/claude-sonnet-5` |

The API request is a one-turn, non-streaming `POST /chat/completions` request
with temperature `0`, `2048` maximum output tokens, and a `120` second timeout.
Provider fallbacks are disabled, and the route is recorded as
`openrouter-chat-completions`.

## Workflow overrides

`--target-models` accepts a comma- or newline-separated list and replaces the
entire default list. It never appends to the defaults. `--judge-model` accepts
exactly one model and replaces the default judge; the resulting judge metadata
states that it applies uniformly to every target in the run.

```bash
evals/api-evaluation-profile.sh \
  --target-models 'openai/eval-target,x-ai/eval-target' \
  --judge-model 'anthropic/eval-judge' \
  --output "$RUNNER_TEMP/api-profile.json"
```

Model identifiers must use an explicit `provider/model` form. Floating routes
such as `openrouter/auto`, `openrouter/free`, and `latest`/`default` aliases
are rejected because they cannot provide a reproducible canonical identifier.
The current profile supports the OpenRouter provider only.

## Operational boundary for live runs

The profile is intended to feed a protected/manual workflow. Static validation
and mocked contract tests must remain credential-free; real model-backed runs
must use an explicitly approved environment with bounded request time, turn
count, concurrency, and cost. The workflow should persist a normalized profile
snapshot and bounded result metadata, but never raw provider transcripts,
authorization headers, credentials, or unrestricted upstream artifacts.

This is a deliberately narrow operational borrowing from native eval harnesses:
it informs the live-run boundary and provenance discipline, but does not import
their native CLI launch modes, interactive QA driver, workspace checks, or
release-gating behavior.

When a caller has a pinned availability snapshot, `--model-catalog PATH` accepts
a non-empty JSON array of exact model identifiers. A requested model absent
from that snapshot produces the typed `model_unavailable` result. Without a
snapshot, availability remains `pending` for the later provider adapter; the
profile does not perform dynamic model discovery.

## Result contract

A valid result has `status: valid` and `result_type: profile`. It preserves
each requested identifier in `requested_model`, records the current canonical
candidate in `canonical_model`, and leaves `resolved_model` as `null` with
`resolution_status: pending` until the provider adapter reports its response.
With a pinned catalog, the status is `catalog_verified`; the exact requested
identifier is still preserved as the canonical candidate.
`substitution_applied` is always `false` in this profile; later adapters must
record any provider resolution explicitly rather than silently changing a
model.

Malformed, unavailable, or unsupported configuration emits JSON with
`result_type: infrastructure`, `status: invalid`, and a typed
`error.category`/`error.code`, then exits with status `2`. The unavailable
profile case covers floating model routes; provider-side model availability
failures are classified by the API adapter using the same typed result shape.
