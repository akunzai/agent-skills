#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$ROOT_DIR/evals/api-evaluation-profile.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "api evaluation profile check failed: $*" >&2
  exit 1
}

expect_invalid() {
  local name="$1"
  local expected_code="$2"
  shift 2
  local result_file="$TEMP_DIR/$name.json"
  local exit_code

  set +e
  "$PROFILE" "$@" >"$result_file"
  exit_code=$?
  set -e

  [ "$exit_code" -eq 2 ] || fail "$name must exit with typed configuration status 2"
  jq -e --arg expected_code "$expected_code" '
    .schema_version == 1
    and .profile == "api-skill-utility-v1"
    and .status == "invalid"
    and .result_type == "infrastructure"
    and .error.type == "infrastructure"
    and .error.code == $expected_code
    and (.error.message | type == "string")
  ' "$result_file" >/dev/null || fail "$name did not emit the expected typed result"
}

[ -x "$PROFILE" ] || fail "profile runner is missing or not executable"

DEFAULT_RESULT="$TEMP_DIR/default.json"
"$PROFILE" >"$DEFAULT_RESULT"
jq -e '
  .schema_version == 1
  and .profile == "api-skill-utility-v1"
  and .status == "valid"
  and .result_type == "profile"
  and .target_models == [
    "openai/gpt-5.6-terra",
    "x-ai/grok-4.6",
    "google/gemini-3.7-flash"
  ]
  and .judge_model == "anthropic/claude-sonnet-5"
  and .replicate_count == 5
  and .selection.target_models_source == "default"
  and .selection.judge_model_source == "default"
  and .provider_routing.provider == "openrouter"
  and .provider_routing.gateway == "openrouter-chat-completions"
  and .provider_routing.base_url == "https://openrouter.ai/api/v1"
  and .provider_routing.allow_fallbacks == false
  and .request.method == "POST"
  and .request.endpoint == "/chat/completions"
  and .request.temperature == null
  and .request.max_tokens == 4096
  and .request.stream == false
  and .request.max_turns == 1
  and .request.timeout_seconds == 120
  and (.target_model_metadata | length == 3)
  and ([.target_model_metadata[].requested_model] == .target_models)
  and ([.target_model_metadata[].canonical_model] == .target_models)
  and ([.target_model_metadata[].resolved_model] | all(. == null))
  and ([.target_model_metadata[].resolution_status] | all(. == "pending"))
  and ([.target_model_metadata[].provider] | all(. == "openrouter"))
  and .judge.requested_model == .judge_model
  and .judge.canonical_model == .judge_model
  and .judge.resolved_model == null
  and .judge.resolution_status == "pending"
  and .judge.applies_to == "all_target_models"
' "$DEFAULT_RESULT" >/dev/null || fail "default profile does not satisfy the public contract"

OVERRIDE_RESULT="$TEMP_DIR/override.json"
"$PROFILE" \
  --target-models 'openai/eval-target,google/eval-target' \
  --judge-model 'anthropic/eval-judge' \
  --replicate-count 2 \
  >"$OVERRIDE_RESULT"
jq -e '
  .status == "valid"
  and .target_models == ["openai/eval-target", "google/eval-target"]
  and .judge_model == "anthropic/eval-judge"
  and .replicate_count == 2
  and .selection.target_models_source == "workflow_input"
  and .selection.judge_model_source == "workflow_input"
  and (.target_model_metadata | length == 2)
  and ([.target_model_metadata[].requested_model] | sort == ["google/eval-target", "openai/eval-target"])
  and ([.target_model_metadata[].judge_model] | unique == ["anthropic/eval-judge"])
  and ([.target_model_metadata[].provider_routing.gateway] | unique == ["openrouter-chat-completions"])
  and .judge.applies_to == "all_target_models"
  and .judge.target_count == 2
' "$OVERRIDE_RESULT" >/dev/null || fail "workflow inputs must replace defaults and share one judge"

SERIALIZED_RESULT="$TEMP_DIR/serialized.json"
"$PROFILE" \
  --target-models $'x-ai/one\ngoogle/two' \
  --judge-model 'anthropic/judge' \
  --output "$SERIALIZED_RESULT"
jq -e '
  .target_models == ["x-ai/one", "google/two"]
  and .judge_model == "anthropic/judge"
  and ([.target_model_metadata[], .judge] | all(
    (.requested_model | type == "string")
    and (.canonical_model | type == "string")
    and (.resolved_model == null)
    and (.provider_routing.provider == "openrouter")
    and (.request.timeout_seconds == 120)
  ))
' "$SERIALIZED_RESULT" >/dev/null || fail "metadata serialization must preserve bounded routing and request fields"

REPEAT_RESULT="$TEMP_DIR/repeat.json"
"$PROFILE" \
  --target-models $'x-ai/one\ngoogle/two' \
  --judge-model 'anthropic/judge' \
  >"$REPEAT_RESULT"
cmp -s "$SERIALIZED_RESULT" "$REPEAT_RESULT" || fail "the same profile inputs must serialize deterministically"

MODEL_CATALOG="$TEMP_DIR/model-catalog.json"
printf '%s\n' '["x-ai/one", "google/two", "anthropic/judge"]' >"$MODEL_CATALOG"
CATALOG_RESULT="$TEMP_DIR/catalog.json"
"$PROFILE" \
  --target-models $'x-ai/one\ngoogle/two' \
  --judge-model 'anthropic/judge' \
  --model-catalog "$MODEL_CATALOG" \
  >"$CATALOG_RESULT"
jq -e '
  .status == "valid"
  and .availability_validation == "pinned_catalog"
  and ([.target_model_metadata[].resolution_status] | all(. == "catalog_verified"))
  and .judge.resolution_status == "catalog_verified"
' "$CATALOG_RESULT" >/dev/null || fail "a pinned model catalog must verify availability in metadata"

expect_invalid empty-targets target_models_empty --target-models ''
expect_invalid empty-target-entry target_model_empty --target-models 'openai/one,,google/two'
expect_invalid malformed-target model_identifier_malformed --target-models 'gpt-5'
expect_invalid floating-target model_unavailable --target-models 'openrouter/auto'
expect_invalid catalog-unavailable model_unavailable \
  --model-catalog "$MODEL_CATALOG" --target-models 'x-ai/not-listed'
expect_invalid multiple-judges judge_model_count_invalid --judge-model 'anthropic/one,anthropic/two'
expect_invalid invalid-replicate-count replicate_count_invalid --replicate-count 0
expect_invalid judge-in-target-sweep judge_model_in_target_sweep \
  --target-models 'openai/one,google/two' --judge-model 'google/two'
expect_invalid unsupported-provider provider_unsupported --provider direct-xai

echo "api evaluation profile checks passed"
