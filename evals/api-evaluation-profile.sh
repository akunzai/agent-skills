#!/usr/bin/env bash
set -euo pipefail

# This profile is the configuration seam for the API-level skill-utility lane.
# Keep it independent of native agent roles and preserve every model identifier
# exactly as supplied; provider resolution happens after this profile is built.

PROFILE_NAME="api-skill-utility-v1"
SCHEMA_VERSION="1"
DEFAULT_PROVIDER="openrouter"
DEFAULT_GATEWAY="openrouter-chat-completions"
DEFAULT_BASE_URL="https://openrouter.ai/api/v1"
DEFAULT_TARGET_MODELS=(
  "openai/gpt-5.6-terra"
  "x-ai/grok-4.6"
  "google/gemini-3.7-flash"
)
DEFAULT_JUDGE_MODEL="anthropic/claude-sonnet-5"
DEFAULT_REPLICATE_COUNT=5

# The one-turn API lane keeps these settings fixed so a model override changes
# model selection only. The profile records them for reproducibility.
REQUEST_METHOD="POST"
REQUEST_ENDPOINT="/chat/completions"
REQUEST_TEMPERATURE="null"
REQUEST_MAX_TOKENS="4096"
REQUEST_STREAM="false"
REQUEST_MAX_TURNS="1"
REQUEST_TIMEOUT_SECONDS="120"
ROUTING_ALLOW_FALLBACKS="false"
ROUTING_REQUIRE_PARAMETERS="true"

TARGET_MODELS=()
TARGET_MODELS_RAW=""
TARGET_MODELS_SET="false"
JUDGE_MODEL=""
JUDGE_MODEL_SET="false"
REPLICATE_COUNT="$DEFAULT_REPLICATE_COUNT"
REPLICATE_COUNT_SET="false"
TARGET_MODELS_SOURCE="default"
JUDGE_MODEL_SOURCE="default"
PROVIDER="$DEFAULT_PROVIDER"
OUTPUT_PATH=""
MODEL_CATALOG_PATH=""
MODEL_CATALOG_SET="false"
MODEL_CATALOG_JSON=""
AVAILABILITY_SOURCE="provider_pending"

usage() {
  cat <<'EOF'
Usage: api-evaluation-profile.sh [options]

Build the reproducible API-level skill-utility evaluation profile.

Options:
  --target-models LIST  Comma- or newline-separated model ids. Replaces all defaults.
  --judge-model MODEL   One model id. Replaces the default judge for the whole run.
  --replicate-count N   Independent treatment/control pairs per target (default: 5).
  --provider NAME       API provider (openrouter is currently supported).
  --model-catalog PATH  Optional pinned JSON array of available model ids.
  --output PATH         Write the normalized JSON profile to PATH instead of stdout.
  --help                Show this help.
EOF
}

emit_json() {
  local json="$1"

  if [ -n "$OUTPUT_PATH" ]; then
    printf '%s\n' "$json" >"$OUTPUT_PATH"
  else
    printf '%s\n' "$json"
  fi
}

typed_error() {
  local category="$1"
  local code="$2"
  local field="$3"
  local message="$4"
  local result

  result="$(jq -n \
    --arg schema_version "$SCHEMA_VERSION" \
    --arg profile "$PROFILE_NAME" \
    --arg category "$category" \
    --arg code "$code" \
    --arg field "$field" \
    --arg message "$message" \
    '{
      schema_version: ($schema_version | tonumber),
      profile: $profile,
      status: "invalid",
      result_type: "infrastructure",
      error: {
        type: "infrastructure",
        category: $category,
        code: $code,
        field: $field,
        message: $message
      }
    }')"
  emit_json "$result"
  exit 2
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

parse_target_models() {
  local normalized
  local line
  local model
  local raw_trimmed

  raw_trimmed="$(trim "$TARGET_MODELS_RAW")"
  [ -n "$raw_trimmed" ] || typed_error \
    "malformed" "target_models_empty" "target_models" \
    "target_models must contain at least one model identifier."

  normalized="$(printf '%s' "$TARGET_MODELS_RAW" | tr ',' '\n')"
  while IFS= read -r line || [ -n "$line" ]; do
    model="$(trim "$line")"
    [ -n "$model" ] || typed_error \
      "malformed" "target_model_empty" "target_models" \
      "target_models must not contain empty entries."
    TARGET_MODELS+=("$model")
  done <<<"$normalized"

  [ "${#TARGET_MODELS[@]}" -gt 0 ] || typed_error \
    "malformed" "target_models_empty" "target_models" \
    "target_models must contain at least one model identifier."
}

parse_judge_model() {
  local judge_model
  local raw_trimmed

  raw_trimmed="$(trim "$JUDGE_MODEL")"
  [ -n "$raw_trimmed" ] || typed_error \
    "malformed" "judge_model_empty" "judge_model" \
    "judge_model must contain exactly one model identifier."
  if [[ "$JUDGE_MODEL" == *,* || "$JUDGE_MODEL" == *$'\n'* ]]; then
    typed_error \
      "malformed" "judge_model_count_invalid" "judge_model" \
      "judge_model must contain exactly one model identifier."
  fi
  judge_model="$raw_trimmed"
  JUDGE_MODEL="$judge_model"
}

validate_model_identifier() {
  local model="$1"
  local field="$2"

  if ! [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
    typed_error \
      "malformed" "model_identifier_malformed" "$field" \
      "model identifiers must use an explicit provider/model form without whitespace."
  fi

  # OpenRouter's auto/free routes and latest/default aliases are floating
  # selections. They cannot produce a reproducible canonical identifier.
  if [[ "$model" == "openrouter/auto" || "$model" == "openrouter/free" \
    || "$model" == "openrouter/auto-router" \
    || "$model" =~ (^|/)(auto|latest|default)($|:|-) \
    || "$model" == *":latest" || "$model" == *":auto" || "$model" == *":default" ]]; then
    typed_error \
      "unavailable" "model_unavailable" "$field" \
      "model selection must resolve to a fixed provider/model identifier."
  fi

  if [ "$MODEL_CATALOG_SET" = "true" ] \
    && ! jq -e --arg model "$model" 'index($model) != null' \
      <<<"$MODEL_CATALOG_JSON" >/dev/null; then
    typed_error \
      "unavailable" "model_unavailable" "$field" \
      "the model is not present in the supplied pinned availability catalog."
  fi
}

validate_target_models() {
  local index

  for index in "${!TARGET_MODELS[@]}"; do
    validate_model_identifier "${TARGET_MODELS[$index]}" "target_models[$index]"
  done
}

validate_judge_independence() {
  local target_model

  for target_model in "${TARGET_MODELS[@]}"; do
    if [ "$target_model" = "$JUDGE_MODEL" ]; then
      typed_error \
        "malformed" "judge_model_in_target_sweep" "judge_model" \
        "judge_model must not appear in target_models; the judge must be independent of the target sweep."
    fi
  done
}

validate_provider() {
  case "$PROVIDER" in
    openrouter) ;;
    *)
      typed_error \
        "unsupported" "provider_unsupported" "provider" \
        "the API evaluation profile currently supports only the OpenRouter provider."
      ;;
  esac
}

build_profile() {
  local target_models_json
  local profile_json

  target_models_json="$(printf '%s\n' "${TARGET_MODELS[@]}" | jq -Rsc '
    split("\n") | if . == [""] then [] else .[:-1] end
  ')"

  profile_json="$(jq -n \
    --arg schema_version "$SCHEMA_VERSION" \
    --arg profile "$PROFILE_NAME" \
    --argjson target_models "$target_models_json" \
    --arg target_models_source "$TARGET_MODELS_SOURCE" \
    --arg judge_model "$JUDGE_MODEL" \
    --arg judge_model_source "$JUDGE_MODEL_SOURCE" \
    --argjson replicate_count "$REPLICATE_COUNT" \
      --arg provider "$PROVIDER" \
      --arg gateway "$DEFAULT_GATEWAY" \
      --arg base_url "$DEFAULT_BASE_URL" \
      --arg availability_source "$AVAILABILITY_SOURCE" \
    --arg request_method "$REQUEST_METHOD" \
    --arg request_endpoint "$REQUEST_ENDPOINT" \
    --argjson request_temperature "$REQUEST_TEMPERATURE" \
    --argjson request_max_tokens "$REQUEST_MAX_TOKENS" \
    --argjson request_stream "$REQUEST_STREAM" \
    --argjson request_max_turns "$REQUEST_MAX_TURNS" \
    --argjson request_timeout_seconds "$REQUEST_TIMEOUT_SECONDS" \
    --argjson allow_fallbacks "$ROUTING_ALLOW_FALLBACKS" \
    --argjson require_parameters "$ROUTING_REQUIRE_PARAMETERS" \
    '
      def request_settings: {
        method: $request_method,
        endpoint: $request_endpoint,
        temperature: $request_temperature,
        max_tokens: $request_max_tokens,
        stream: $request_stream,
        max_turns: $request_max_turns,
        timeout_seconds: $request_timeout_seconds
      };
      def provider_routing: {
        provider: $provider,
        gateway: $gateway,
        base_url: $base_url,
        allow_fallbacks: $allow_fallbacks,
        require_parameters: $require_parameters
      };
      def model_metadata($model): {
        requested_model: $model,
        canonical_model: $model,
        resolved_model: null,
        resolution_status: (
          if $availability_source == "pinned_catalog"
          then "catalog_verified"
          else "pending"
          end
        ),
        substitution_applied: false,
        provider: $provider,
        gateway: $gateway,
        provider_routing: provider_routing,
        request: request_settings
      };
      {
        schema_version: ($schema_version | tonumber),
        profile: $profile,
        status: "valid",
        result_type: "profile",
        selection: {
          target_models_source: $target_models_source,
          judge_model_source: $judge_model_source
        },
        target_models: $target_models,
        judge_model: $judge_model,
        replicate_count: $replicate_count,
        availability_validation: $availability_source,
        provider_routing: provider_routing,
        request: request_settings,
        target_model_metadata: (
          $target_models
          | map(model_metadata(.) + {judge_model: $judge_model})
        ),
        judge: (
          model_metadata($judge_model)
          + {
            applies_to: "all_target_models",
            target_count: ($target_models | length)
          }
        )
      }
    ')"
  emit_json "$profile_json"
}

command -v jq >/dev/null 2>&1 || {
  echo "api evaluation profile: jq executable not found" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-models)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "target_models" \
        "--target-models requires a value."
      [ "$TARGET_MODELS_SET" = "false" ] || typed_error \
        "malformed" "option_duplicate" "target_models" \
        "--target-models may be supplied only once."
      TARGET_MODELS_RAW="$2"
      TARGET_MODELS_SET="true"
      TARGET_MODELS_SOURCE="workflow_input"
      shift 2
      ;;
    --judge-model)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "judge_model" \
        "--judge-model requires a value."
      [ "$JUDGE_MODEL_SET" = "false" ] || typed_error \
        "malformed" "option_duplicate" "judge_model" \
        "--judge-model may be supplied only once."
      JUDGE_MODEL="$2"
      JUDGE_MODEL_SET="true"
      JUDGE_MODEL_SOURCE="workflow_input"
      shift 2
      ;;
    --provider)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "provider" \
        "--provider requires a value."
      PROVIDER="$2"
      shift 2
      ;;
    --replicate-count)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "replicate_count" \
        "--replicate-count requires a value."
      [ "$REPLICATE_COUNT_SET" = "false" ] || typed_error \
        "malformed" "option_duplicate" "replicate_count" \
        "--replicate-count may be supplied only once."
      REPLICATE_COUNT="$2"
      REPLICATE_COUNT_SET="true"
      shift 2
      ;;
    --model-catalog)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "model_catalog" \
        "--model-catalog requires a path."
      [ "$MODEL_CATALOG_SET" = "false" ] || typed_error \
        "malformed" "option_duplicate" "model_catalog" \
        "--model-catalog may be supplied only once."
      MODEL_CATALOG_PATH="$2"
      MODEL_CATALOG_SET="true"
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || typed_error \
        "malformed" "option_value_missing" "output" \
        "--output requires a path."
      OUTPUT_PATH="$2"
      [ -n "$OUTPUT_PATH" ] || typed_error \
        "malformed" "output_path_empty" "output" \
        "--output requires a non-empty path."
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      typed_error \
        "malformed" "option_unsupported" "options" \
        "the profile received an unsupported option."
      ;;
  esac
done

validate_provider

[[ "$REPLICATE_COUNT" =~ ^[1-9][0-9]*$ ]] || typed_error \
  "malformed" "replicate_count_invalid" "replicate_count" \
  "replicate_count must be a positive integer."

if [ "$TARGET_MODELS_SET" = "true" ]; then
  parse_target_models
else
  TARGET_MODELS=("${DEFAULT_TARGET_MODELS[@]}")
fi

if [ "$JUDGE_MODEL_SET" = "false" ]; then
  JUDGE_MODEL="$DEFAULT_JUDGE_MODEL"
else
  parse_judge_model
fi

if [ "$MODEL_CATALOG_SET" = "true" ]; then
  [ -f "$MODEL_CATALOG_PATH" ] || typed_error \
    "unavailable" "model_catalog_unavailable" "model_catalog" \
    "the supplied model availability catalog is not available."
  if ! jq -e '
    type == "array"
    and length > 0
    and all(.[]; type == "string"
      and test("^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*$"))
  ' "$MODEL_CATALOG_PATH" >/dev/null 2>&1; then
    typed_error \
      "malformed" "model_catalog_malformed" "model_catalog" \
      "the model availability catalog must be a non-empty JSON array of model identifiers."
  fi
  MODEL_CATALOG_JSON="$(jq -c . "$MODEL_CATALOG_PATH")"
  AVAILABILITY_SOURCE="pinned_catalog"
fi

validate_target_models
validate_model_identifier "$JUDGE_MODEL" "judge_model"
validate_judge_independence
build_profile
