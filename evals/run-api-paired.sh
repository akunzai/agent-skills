#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/api-paired"
PROFILE_RUNNER="$ROOT_DIR/evals/api-evaluation-profile.sh"
CURL_BIN="${CURL_BIN:-curl}"

PROFILE_PATH=""
TASK_FILE=""
SKILL_FILE=""
SKILL_NAME=""
FIXTURE_REVISION=""
ARTIFACT_DIR="$DEFAULT_ARTIFACT_DIR"

TEMP_DIR=""
PROFILE_SCHEMA_VERSION=""
PROFILE_NAME=""
TARGET_MODELS_JSON=""
TARGET_MODELS=()
JUDGE_MODEL=""
REQUEST_JSON=""
ROUTING_JSON=""
ROUTING_BASE_URL=""
REQUEST_PROVIDER_JSON=""
REQUEST_ENDPOINT=""
REQUEST_TEMPERATURE=""
REQUEST_MAX_TOKENS=""
REQUEST_STREAM=""
REQUEST_TIMEOUT_SECONDS=""
TASK_HASH=""
SKILL_HASH=""
REQUEST_INDEX=0

usage() {
  cat <<'EOF'
Usage: run-api-paired.sh [options]

Run one-turn treatment/control requests for every target in an API profile.

Options:
  --profile PATH          Validated API evaluation profile JSON.
  --task-file PATH        Natural-language task sent to both conditions.
  --skill-file PATH       One selected skill supplied only to treatment.
  --skill-name NAME       Stable name recorded for the selected skill.
  --fixture-revision REV  Pinned task/skill fixture revision.
  --artifact-dir PATH     Directory for normalized, redacted results.
  --help                  Show this help.
EOF
}

write_failure() {
  local category="$1"
  local code="$2"
  local field="$3"
  local message="$4"

  mkdir -p "$ARTIFACT_DIR"
  jq -n \
    --arg profile "$PROFILE_NAME" \
    --arg schema_version "$PROFILE_SCHEMA_VERSION" \
    --arg category "$category" \
    --arg code "$code" \
    --arg field "$field" \
    --arg message "$message" \
    '{
      schema_version: (if ($schema_version | test("^[0-9]+$")) then ($schema_version | tonumber) else 1 end),
      suite: "api-skill-utility",
      runner: "openrouter-one-turn-paired",
      result_type: "infrastructure",
      status: "failed",
      outcome: "not-scored",
      profile: (if $profile == "" then null else $profile end),
      error: {
        type: "infrastructure",
        category: $category,
        code: $code,
        field: $field,
        message: $message
      }
    }' >"$ARTIFACT_DIR/results.json"
  echo "api paired evaluation: $code" >&2
  exit 2
}

sha256_file() {
  local path="$1"
  printf 'sha256:%s' "$(shasum -a 256 "$path" | awk '{print $1}')"
}

classify_stderr() {
  local error_file="$1"

  if [ ! -s "$error_file" ]; then
    printf '%s\n' 'empty'
  elif grep -Eqi 'timed out|timeout|deadline exceeded' "$error_file"; then
    printf '%s\n' 'timeout'
  elif grep -Eqi 'unauthori[sz]ed|authentication|api[ _-]?key|credential|\b401\b' \
    "$error_file"; then
    printf '%s\n' 'authentication_rejected'
  elif grep -Eqi 'rate limit|too many requests|\b429\b' "$error_file"; then
    printf '%s\n' 'rate_limited'
  else
    printf '%s\n' 'transport_error'
  fi
}

build_request() {
  local model="$1"
  local condition="$2"
  local request_file="$3"

  jq -n \
    --arg model "$model" \
    --arg condition "$condition" \
    --arg skill_name "$SKILL_NAME" \
    --rawfile task "$TASK_FILE" \
    --rawfile skill "$SKILL_FILE" \
    --argjson temperature "$REQUEST_TEMPERATURE" \
    --argjson max_tokens "$REQUEST_MAX_TOKENS" \
    --argjson stream "$REQUEST_STREAM" \
    --argjson provider "$REQUEST_PROVIDER_JSON" \
    '{
      model: $model,
      messages: (
        [{
          role: "system",
          content: ("Complete the user task using only the request context. " +
            "Do not use slash commands or claim unobserved actions.")
        }]
        + (if $condition == "treatment" then [{
            role: "system",
            content: ("SKILL-CONTEXT (exactly one selected skill): " +
              $skill_name + "\n\n" + $skill)
          }] else [] end)
        + [{role: "user", content: $task}]
      ),
      temperature: $temperature,
      max_tokens: $max_tokens,
      stream: $stream,
      provider: $provider
    }' >"$request_file"
}

classify_response_error() {
  local http_status="$1"
  local response_file="$2"

  case "$http_status" in
    401|403)
      printf '%s\n' 'credentials_rejected'
      ;;
    404)
      printf '%s\n' 'model_unavailable'
      ;;
    408|504)
      printf '%s\n' 'request_timeout'
      ;;
    429)
      printf '%s\n' 'provider_rate_limited'
      ;;
    2??)
      if jq -e '.error != null' "$response_file" >/dev/null 2>&1; then
        if grep -Eqi 'model.*(not found|unavailable)|no endpoints|\b404\b' "$response_file"; then
          printf '%s\n' 'model_unavailable'
        else
          printf '%s\n' 'provider_error'
        fi
      elif ! jq -e '
        ((.choices | type) == "array")
        and ((.choices | length) > 0)
        and ((.choices[0].message.content | type) == "string")
      ' "$response_file" >/dev/null 2>&1; then
        printf '%s\n' 'response_malformed'
      else
        printf '%s\n' ''
      fi
      ;;
    *)
      printf '%s\n' 'provider_error'
      ;;
  esac
}

error_category() {
  case "$1" in
    credentials_rejected)
      printf '%s\n' 'credentials'
      ;;
    model_unavailable)
      printf '%s\n' 'model'
      ;;
    request_timeout|provider_transport_error)
      printf '%s\n' 'transport'
      ;;
    response_malformed)
      printf '%s\n' 'response'
      ;;
    provider_rate_limited|provider_error)
      printf '%s\n' 'provider'
      ;;
    *)
      printf '%s\n' 'provider'
      ;;
  esac
}

CONDITION_RESULT=""
CONDITION_FAILED="false"

process_condition() {
  local model="$1"
  local condition="$2"
  local request_file
  local response_file
  local stderr_file
  local http_status_file
  local curl_exit
  local http_status
  local response_state="empty"
  local stderr_category
  local stderr_fingerprint=""
  local response_fingerprint=""
  local error_code=""
  local error_category_value=""
  local resolved_model=""
  local resolution_status="not-reported"
  local usage_json="null"
  local finish_reason=""
  local request_hash

  REQUEST_INDEX=$((REQUEST_INDEX + 1))
  request_file="$TEMP_DIR/request-$REQUEST_INDEX.json"
  response_file="$TEMP_DIR/response-$REQUEST_INDEX.json"
  stderr_file="$TEMP_DIR/stderr-$REQUEST_INDEX.txt"
  http_status_file="$TEMP_DIR/status-$REQUEST_INDEX.txt"

  build_request "$model" "$condition" "$request_file"
  request_hash="$(sha256_file "$request_file")"

  set +e
  "$CURL_BIN" \
    --silent \
    --show-error \
    --connect-timeout "$REQUEST_TIMEOUT_SECONDS" \
    --max-time "$REQUEST_TIMEOUT_SECONDS" \
    --request POST \
    --header "Authorization: Bearer $OPENROUTER_API_KEY" \
    --header 'Content-Type: application/json' \
    --data-binary "@$request_file" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "${ROUTING_BASE_URL%/}$REQUEST_ENDPOINT" \
    >"$http_status_file" \
    2>"$stderr_file"
  curl_exit=$?
  set -e

  http_status="$(tr -d '\r\n' <"$http_status_file")"
  if [ -s "$response_file" ]; then
    if jq -e . "$response_file" >/dev/null 2>&1; then
      response_state="valid_json"
    else
      response_state="invalid_json"
    fi
  fi

  stderr_category="$(classify_stderr "$stderr_file")"
  if [ -s "$stderr_file" ]; then
    stderr_fingerprint="$(sha256_file "$stderr_file")"
  fi
  if [ -s "$response_file" ]; then
    response_fingerprint="$(sha256_file "$response_file")"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    if [ "$curl_exit" -eq 28 ] || [ "$stderr_category" = "timeout" ]; then
      error_code="request_timeout"
    else
      error_code="provider_transport_error"
    fi
  elif ! [[ "$http_status" =~ ^[0-9]{3}$ ]]; then
    error_code="provider_transport_error"
  elif [[ ! "$http_status" =~ ^2[0-9]{2}$ ]]; then
    error_code="$(classify_response_error "$http_status" "$response_file")"
  elif [ "$response_state" != "valid_json" ]; then
    error_code="response_malformed"
  else
    error_code="$(classify_response_error "$http_status" "$response_file")"
  fi

  if [ "$response_state" = "valid_json" ]; then
    resolved_model="$(jq -r '
      if (.model | type) == "string" and .model != "" then .model else empty end
    ' "$response_file" 2>/dev/null || true)"
    if [ -n "$resolved_model" ]; then
      resolution_status="reported"
    fi
    finish_reason="$(jq -r '
      if (.choices[0].finish_reason | type) == "string" then .choices[0].finish_reason else empty end
    ' "$response_file" 2>/dev/null || true)"
    usage_json="$(jq -c '
      if (.usage | type) == "object" then {
        prompt_tokens: (if (.usage.prompt_tokens | type) == "number" then .usage.prompt_tokens else null end),
        completion_tokens: (
          if (.usage.completion_tokens | type) == "number"
          then .usage.completion_tokens
          else null
          end
        ),
        total_tokens: (if (.usage.total_tokens | type) == "number" then .usage.total_tokens else null end),
        cost_usd: (if (.usage.cost | type) == "number" then .usage.cost else null end)
      } else null end
    ' "$response_file" 2>/dev/null || printf '%s' 'null')"
  fi

  CONDITION_FAILED="false"
  if [ -n "$error_code" ]; then
    CONDITION_FAILED="true"
    error_category_value="$(error_category "$error_code")"
  fi

  skill_context="absent"
  result_skill_name=""
  if [ "$condition" = "treatment" ]; then
    skill_context="present"
    result_skill_name="$SKILL_NAME"
  fi

  CONDITION_RESULT="$(jq -n \
    --arg condition "$condition" \
    --arg model "$model" \
    --arg skill_context "$skill_context" \
    --arg skill_name "$result_skill_name" \
    --arg task_hash "$TASK_HASH" \
    --arg request_hash "$request_hash" \
    --arg status "$([ -n "$error_code" ] && printf '%s' 'failed' || printf '%s' 'response_received')" \
    --arg error_code "$error_code" \
    --arg error_category "$error_category_value" \
    --arg http_status "$http_status" \
    --arg response_state "$response_state" \
    --arg resolved_model "$resolved_model" \
    --arg resolution_status "$resolution_status" \
    --arg finish_reason "$finish_reason" \
    --arg stderr_category "$stderr_category" \
    --arg stderr_fingerprint "$stderr_fingerprint" \
    --arg response_fingerprint "$response_fingerprint" \
    --argjson curl_exit "$curl_exit" \
    --argjson usage "$usage_json" \
    '{
      condition: $condition,
      requested_model: $model,
      status: $status,
      outcome: "not-scored",
      request_count: 1,
      skill_context: $skill_context,
      skill_name: (if $skill_name == "" then null else $skill_name end),
      task_sha256: $task_hash,
      request_sha256: $request_hash,
      response: {
        state: $response_state,
        http_status: (if ($http_status | test("^[0-9]{3}$")) then ($http_status | tonumber) else null end),
        curl_exit: $curl_exit,
        resolved_model: (if $resolved_model == "" then null else $resolved_model end),
        resolution_status: $resolution_status,
        finish_reason: (if $finish_reason == "" then null else $finish_reason end),
        usage: $usage,
        content: null,
        response_sha256: (if $response_fingerprint == "" then null else $response_fingerprint end)
      }
    }
    + (if $error_code == "" then {}
       else {
         error: {
           type: "infrastructure",
           category: $error_category,
           code: $error_code,
           message: "The provider request did not produce a valid model response.",
           diagnostics: {
             response_state: $response_state,
             stderr_category: $stderr_category,
             stderr_sha256: (if $stderr_fingerprint == "" then null else $stderr_fingerprint end)
           }
         }
       }
       end)' )"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --profile requires a path" >&2; exit 2; }
      PROFILE_PATH="$2"
      shift 2
      ;;
    --task-file)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --task-file requires a path" >&2; exit 2; }
      TASK_FILE="$2"
      shift 2
      ;;
    --skill-file)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --skill-file requires a path" >&2; exit 2; }
      SKILL_FILE="$2"
      shift 2
      ;;
    --skill-name)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --skill-name requires a value" >&2; exit 2; }
      SKILL_NAME="$2"
      shift 2
      ;;
    --fixture-revision)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --fixture-revision requires a value" >&2; exit 2; }
      FIXTURE_REVISION="$2"
      shift 2
      ;;
    --artifact-dir)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --artifact-dir requires a path" >&2; exit 2; }
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "api paired evaluation: unsupported option: $1" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "api paired evaluation: jq executable not found" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "api paired evaluation: shasum executable not found" >&2; exit 1; }
command -v "$CURL_BIN" >/dev/null 2>&1 || { echo "api paired evaluation: curl executable not found" >&2; exit 1; }

mkdir -p "$ARTIFACT_DIR"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [ -z "$PROFILE_PATH" ]; then
  PROFILE_PATH="$TEMP_DIR/profile.json"
  if ! "$PROFILE_RUNNER" --output "$PROFILE_PATH" >/dev/null 2>"$TEMP_DIR/profile-error.txt"; then
    write_failure "configuration" "profile_invalid" "profile" \
      "the API evaluation profile could not be validated."
  fi
fi

[ -f "$PROFILE_PATH" ] || write_failure "configuration" "profile_unavailable" "profile" \
  "the supplied API evaluation profile is not available."
[ -s "$TASK_FILE" ] || write_failure "configuration" "task_fixture_invalid" "task_file" \
  "the task fixture must be a non-empty file."
[ -s "$SKILL_FILE" ] || write_failure "configuration" "skill_fixture_invalid" "skill_file" \
  "the selected skill fixture must be a non-empty file."
[ -n "$FIXTURE_REVISION" ] || write_failure "configuration" "fixture_revision_missing" "fixture_revision" \
  "the fixture revision must be provided."
if [[ "$FIXTURE_REVISION" == *$'\n'* || "$SKILL_NAME" == *$'\n'* ]]; then
  write_failure "configuration" "fixture_metadata_malformed" "fixture" \
    "fixture metadata must not contain newlines."
fi
[ -n "$SKILL_NAME" ] || SKILL_NAME="$(basename "$(dirname "$SKILL_FILE")")"
[ -n "$SKILL_NAME" ] || write_failure "configuration" "skill_name_missing" "skill_name" \
  "the selected skill must have a stable name."

if ! jq -e '
  .schema_version == 1
  and
  .status == "valid"
  and .result_type == "profile"
  and (.target_models | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
  and (.judge_model | type == "string" and length > 0)
  and .provider_routing.provider == "openrouter"
  and .provider_routing.gateway == "openrouter-chat-completions"
  and (.provider_routing.base_url | test("^https://openrouter\\.ai/api/v1/?$"))
  and .provider_routing.allow_fallbacks == false
  and .provider_routing.require_parameters == true
  and .request.method == "POST"
  and .request.endpoint == "/chat/completions"
  and (.request.temperature | type == "number")
  and (.request.max_tokens | type == "number" and . > 0)
  and .request.stream == false
  and .request.max_turns == 1
  and (.request.timeout_seconds | type == "number" and . > 0)
  and ((.target_model_metadata | type) == "array")
  and ((.target_model_metadata | length) == (.target_models | length))
  and ([.target_model_metadata[].requested_model] == .target_models)
' "$PROFILE_PATH" >/dev/null 2>&1; then
  write_failure "configuration" "profile_invalid" "profile" \
    "the profile must be a valid one-turn OpenRouter evaluation profile."
fi

PROFILE_SCHEMA_VERSION="$(jq -r '.schema_version // 1' "$PROFILE_PATH")"
PROFILE_NAME="$(jq -r '.profile' "$PROFILE_PATH")"
TARGET_MODELS_JSON="$(jq -c '.target_models' "$PROFILE_PATH")"
mapfile -t TARGET_MODELS < <(jq -r '.target_models[]' "$PROFILE_PATH")
JUDGE_MODEL="$(jq -r '.judge_model' "$PROFILE_PATH")"
REQUEST_JSON="$(jq -c '{
  method: .request.method,
  endpoint: .request.endpoint,
  temperature: .request.temperature,
  max_tokens: .request.max_tokens,
  stream: .request.stream,
  max_turns: .request.max_turns,
  timeout_seconds: .request.timeout_seconds
}' "$PROFILE_PATH")"
ROUTING_JSON="$(jq -c '{
  provider: .provider_routing.provider,
  gateway: .provider_routing.gateway,
  base_url: .provider_routing.base_url,
  allow_fallbacks: .provider_routing.allow_fallbacks,
  require_parameters: .provider_routing.require_parameters
}' "$PROFILE_PATH")"
ROUTING_BASE_URL="$(jq -r '.provider_routing.base_url' "$PROFILE_PATH")"
REQUEST_ENDPOINT="$(jq -r '.request.endpoint' "$PROFILE_PATH")"
REQUEST_TEMPERATURE="$(jq -r '.request.temperature' "$PROFILE_PATH")"
REQUEST_MAX_TOKENS="$(jq -r '.request.max_tokens' "$PROFILE_PATH")"
REQUEST_STREAM="$(jq -r '.request.stream' "$PROFILE_PATH")"
REQUEST_TIMEOUT_SECONDS="$(jq -r '.request.timeout_seconds' "$PROFILE_PATH")"
REQUEST_PROVIDER_JSON="$(jq -c '{
  allow_fallbacks: .provider_routing.allow_fallbacks,
  require_parameters: .provider_routing.require_parameters
}' "$PROFILE_PATH")"

TASK_HASH="$(sha256_file "$TASK_FILE")"
SKILL_HASH="$(sha256_file "$SKILL_FILE")"

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  write_failure "credentials" "credential_missing" "OPENROUTER_API_KEY" \
    "the OpenRouter credential is required for model-backed execution."
fi

PAIRS_NDJSON="$TEMP_DIR/pairs.ndjson"
OVERALL_FAILURE="false"

for model in "${TARGET_MODELS[@]}"; do
  process_condition "$model" "treatment"
  treatment_result="$CONDITION_RESULT"
  treatment_failed="$CONDITION_FAILED"

  process_condition "$model" "control"
  control_result="$CONDITION_RESULT"
  control_failed="$CONDITION_FAILED"

  pair_status="completed"
  if [ "$treatment_failed" = "true" ] || [ "$control_failed" = "true" ]; then
    pair_status="failed"
    OVERALL_FAILURE="true"
  fi

  jq -n \
    --arg model "$model" \
    --arg fixture_revision "$FIXTURE_REVISION" \
    --arg task_hash "$TASK_HASH" \
    --arg skill_hash "$SKILL_HASH" \
    --arg pair_status "$pair_status" \
    --argjson request "$REQUEST_JSON" \
    --argjson routing "$ROUTING_JSON" \
    --argjson treatment "$treatment_result" \
    --argjson control "$control_result" \
    '{
      target_model: $model,
      fixture_revision: $fixture_revision,
      task_sha256: $task_hash,
      skill_sha256: $skill_hash,
      request: $request,
      provider_routing: $routing,
      status: $pair_status,
      outcome: "not-scored",
      treatment: $treatment,
      control: $control
    }' >>"$PAIRS_NDJSON"
done

PAIRS_JSON="$(jq -s . "$PAIRS_NDJSON")"
OVERALL_STATUS="completed"
if [ "$OVERALL_FAILURE" = "true" ]; then
  OVERALL_STATUS="failed"
fi

jq -n \
  --arg schema_version "$PROFILE_SCHEMA_VERSION" \
  --arg profile "$PROFILE_NAME" \
  --arg status "$OVERALL_STATUS" \
  --arg fixture_revision "$FIXTURE_REVISION" \
  --arg skill_name "$SKILL_NAME" \
  --arg task_hash "$TASK_HASH" \
  --arg skill_hash "$SKILL_HASH" \
  --arg judge_model "$JUDGE_MODEL" \
  --argjson target_models "$TARGET_MODELS_JSON" \
  --argjson request "$REQUEST_JSON" \
  --argjson routing "$ROUTING_JSON" \
  --argjson pairs "$PAIRS_JSON" \
  '{
    schema_version: ($schema_version | tonumber),
    suite: "api-skill-utility",
    runner: "openrouter-one-turn-paired",
    result_type: "paired_results",
    status: $status,
    outcome: "not-scored",
    profile: {name: $profile},
    fixture: {
      revision: $fixture_revision,
      skill_name: $skill_name,
      task_sha256: $task_hash,
      skill_sha256: $skill_hash
    },
    target_models: $target_models,
    judge_model: $judge_model,
    provider_routing: $routing,
    request: $request,
    pairs: $pairs
  }' >"$ARTIFACT_DIR/results.json"

if [ "$OVERALL_FAILURE" = "true" ]; then
  echo "API paired evaluation failed: $ARTIFACT_DIR/results.json" >&2
  exit 1
fi

echo "API paired evaluation completed: $ARTIFACT_DIR/results.json"
