#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/api-paired"
PROFILE_RUNNER="$ROOT_DIR/evals/api-evaluation-profile.sh"
CURL_BIN="${CURL_BIN:-curl}"

PROFILE_PATH=""
TASK_FILE=""
TASK_REVISION=""
SKILL_FILE=""
SKILL_REVISION=""
SKILL_NAME=""
FIXTURE_REVISION=""
RUBRIC_FILE=""
RUBRIC_REVISION=""
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
REQUEST_METHOD=""
REQUEST_MAX_TOKENS=""
REQUEST_STREAM=""
REQUEST_MAX_TURNS=""
REQUEST_TIMEOUT_SECONDS=""
TASK_HASH=""
SKILL_HASH=""
RUBRIC_HASH=""
MAX_ARTIFACT_BYTES=""
REQUEST_INDEX=0
JUDGE_MAX_TOKENS=512
JUDGE_REASONING_EFFORT="low"

usage() {
  cat <<'EOF'
Usage: run-api-paired.sh [options]

Run one-turn treatment/control requests for every target in an API profile.

Options:
  --profile PATH          Validated API evaluation profile JSON.
  --task-file PATH        Natural-language task sent to both conditions.
  --task-revision REV     Pinned task fixture revision.
  --skill-file PATH       One selected skill supplied only to treatment.
  --skill-revision REV    Pinned skill fixture revision.
  --skill-name NAME       Stable name recorded for the selected skill.
  --fixture-revision REV  Pinned API fixture revision.
  --rubric-file PATH      Fixed response rubric supplied to the judge.
  --rubric-revision REV   Pinned rubric fixture revision.
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
  printf '::error title=API paired evaluation configuration::code=%s category=%s field=%s message=%s\n' \
    "$code" "$category" "$field" "$message" >&2
  echo "api paired evaluation: code=$code category=$category field=$field message=$message" >&2
  exit 2
}

sha256_file() {
  local path="$1"
  printf 'sha256:%s' "$(shasum -a 256 "$path" | awk '{print $1}')"
}

now_seconds() {
  date +%s
}

progress() {
  printf 'API paired evaluation: %s\n' "$*"
}

report_result() {
  local target_index="$1"
  local target_count="$2"
  local model="$3"
  local phase="$4"
  local result="$5"
  local status
  local http_status
  local error_code
  local duration_seconds
  local cost_status
  local provider_error_type

  status="$(jq -r '.status // "unknown"' <<<"$result")"
  http_status="$(jq -r '.response.http_status // "-"' <<<"$result")"
  error_code="$(jq -r '.error.code // "none"' <<<"$result")"
  duration_seconds="$(jq -r '.timing.duration_seconds // 0' <<<"$result")"
  provider_error_type="$(jq -r '.error.diagnostics.provider_error_type // "none"' <<<"$result")"
  if ! [[ "$provider_error_type" =~ ^[A-Za-z0-9._-]+$ ]]; then
    provider_error_type="untrusted"
  fi
  if jq -e '(.response.usage.cost_usd | type) == "number"' \
    <<<"$result" >/dev/null 2>&1; then
    cost_status="reported"
  else
    cost_status="missing"
  fi

  progress \
    "target=$target_index/$target_count" \
    "model=$model" \
    "phase=$phase" \
    "status=$status" \
    "http=$http_status" \
    "error=$error_code" \
    "provider_error_type=$provider_error_type" \
    "duration=${duration_seconds}s" \
    "cost=$cost_status"
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
      max_tokens: $max_tokens,
      stream: $stream,
      provider: $provider
    }' >"$request_file"
}

provider_error_text() {
  local response_file="$1"

  jq -r '
    [
      (.error.message? // ""),
      (.error.metadata?.message? // "")
    ]
    | map(select(type == "string"))
    | join(" ")
    | ascii_downcase
  ' "$response_file" 2>/dev/null || true
}

response_contains_error_pattern() {
  local response_file="$1"
  local pattern="$2"
  local error_text

  [ -s "$response_file" ] || return 1
  error_text="$(provider_error_text "$response_file")"
  printf '%s\n' "$error_text" | grep -Eqi "$pattern"
}

response_indicates_parameter_mismatch() {
  local response_file="$1"
  local pattern

  pattern='no endpoints found.*support.*parameters?'
  pattern+='|unsupported[^[:space:]]*[[:space:]]+parameters?'
  pattern+='|parameters?[^[:space:]]+not supported'
  pattern+='|does not support[^[:space:]]+parameters?'
  if response_contains_error_pattern "$response_file" "$pattern" \
    || response_indicates_unselected_endpoints "$response_file"; then
    return 0
  fi
  return 1
}

response_indicates_no_provider_endpoint() {
  local response_file="$1"

  response_contains_error_pattern \
    "$response_file" \
    'no allowed providers are available'
}

response_indicates_unselected_endpoints() {
  local response_file="$1"

  jq -e '
    (.openrouter_metadata.endpoints | type) == "object"
    and (.openrouter_metadata.endpoints.available | type) == "array"
    and (.openrouter_metadata.endpoints.available | length) > 0
    and ([.openrouter_metadata.endpoints.available[]
      | select(.selected == true)] | length) == 0
  ' "$response_file" >/dev/null 2>&1
}

extract_provider_error_type() {
  local response_file="$1"
  local error_type

  error_type="$(jq -r '
    if (.error.metadata.error_type | type) == "string" then .error.metadata.error_type
    elif (.error.error_type | type) == "string" then .error.error_type
    elif (.error_type | type) == "string" then .error_type
    else empty
    end
  ' "$response_file" 2>/dev/null || true)"
  if [[ "$error_type" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    printf '%s\n' "$error_type"
  else
    printf '%s\n' ''
  fi
}

extract_router_metadata() {
  local response_file="$1"

  jq -c '
    def bounded_count:
      if type == "number" then
        if (floor == . and . >= 0 and . <= 100000) then . else null end
      else null
      end;
    def bounded_strategy:
      if type == "string" then
        if test("^[A-Za-z0-9._-]{1,64}$") then . else null end
      else null
      end;

    if (.openrouter_metadata | type) == "object" then {
      attempt: (.openrouter_metadata.attempt | bounded_count),
      strategy: (.openrouter_metadata.strategy | bounded_strategy),
      endpoints: (
        if (.openrouter_metadata.endpoints | type) == "object" then {
          total: (.openrouter_metadata.endpoints.total | bounded_count),
          available_count: (
            if (.openrouter_metadata.endpoints.available | type) == "array"
            then (.openrouter_metadata.endpoints.available | length | bounded_count)
            else null
            end
          ),
          selected_count: (
            if (.openrouter_metadata.endpoints.available | type) == "array"
            then ([.openrouter_metadata.endpoints.available[]?
              | select(.selected == true)] | length | bounded_count)
            else null
            end
          )
        } else null end
      )
    } else null end
  ' "$response_file" 2>/dev/null || printf '%s' 'null'
}

extract_response_shape() {
  local response_file="$1"

  jq -c '
    def bounded_key:
      if type == "string" and test("^[A-Za-z0-9._-]{1,64}$") then . else null end;
    def bounded_keys:
      if type == "object"
      then [keys[] | bounded_key | select(. != null)] | .[:32]
      else []
      end;

    {
      top_level_keys: (. | bounded_keys),
      choices_type: (.choices | type),
      choices_count: (
        if (.choices | type) == "array" then (.choices | length) else null end
      ),
      first_choice_type: (.choices[0] | type),
      first_choice_keys: (.choices[0] | bounded_keys),
      message_type: (.choices[0].message | type),
      message_keys: (.choices[0].message | bounded_keys),
      content_type: (.choices[0].message.content | type),
      content_length: (
        if (.choices[0].message.content | type) == "string"
        then (.choices[0].message.content | length)
        else null
        end
      )
    }
  ' "$response_file" 2>/dev/null || printf '%s' 'null'
}

classify_response_error() {
  local http_status="$1"
  local response_file="$2"

  if response_indicates_parameter_mismatch "$response_file"; then
    printf '%s\n' 'request_parameters_unsupported'
    return
  fi
  if response_indicates_no_provider_endpoint "$response_file"; then
    printf '%s\n' 'provider_endpoint_unavailable'
    return
  fi

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
        and ((.choices[0].message.content | type) == "string"
          or (.choices[0].message.content | type) == "object")
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
    request_parameters_unsupported)
      printf '%s\n' 'configuration'
      ;;
    provider_endpoint_unavailable)
      printf '%s\n' 'provider'
      ;;
    provider_rate_limited|provider_error)
      printf '%s\n' 'provider'
      ;;
    *)
      printf '%s\n' 'provider'
      ;;
  esac
}

describe_error() {
  local message

  case "$1" in
    request_parameters_unsupported|judge_request_parameters_unsupported)
      message='No OpenRouter endpoint supports all recorded request parameters; '
      message+='compare the model catalog supported_parameters with the request profile.'
      ;;
    provider_endpoint_unavailable|judge_provider_endpoint_unavailable)
      message='No OpenRouter provider endpoint was available; '
      message+='check model supported_parameters, require_parameters, allow_fallbacks, '
      message+='and provider/account filters.'
      ;;
    *)
      message='The provider request did not produce a valid model response.'
      ;;
  esac

  printf '%s\n' "$message"
}

evaluate_deterministic() {
  local response_text="$1"

  jq -n \
    --arg response "$response_text" \
    --slurpfile rubric "$RUBRIC_FILE" '
      def pass_if($value): if $value then "passed" else "failed" end;
      def bullet_lines:
        $response
        | split("\n")
        | map(select(test("^\\s*([-*+] |[0-9]+[.)] )")));
      def has_context($terms):
        ([$terms[] as $term | select(contains($term))] | length) > 0;

      ([$rubric[0].checks[]
        | select(.kind == "minimum_context_references")
        | .terms[]] | unique) as $context_terms
      | ([$rubric[0].checks[] as $check
        | if $check.kind == "required_headings" then
            ([$check.headings[]
              | select($response | contains(.))]) as $matched
            | {
                id: $check.id,
                kind: $check.kind,
                status: pass_if(($matched | length) == ($check.headings | length)),
                observed_count: ($matched | length),
                expected_count: ($check.headings | length),
                missing: [$check.headings[]
                  | select(($response | contains(.)) | not)]
              }
          elif $check.kind == "minimum_context_references" then
            ([$check.terms[]
              | select($response | contains(.))]) as $matched
            | {
                id: $check.id,
                kind: $check.kind,
                status: pass_if(($matched | length) >= $check.minimum),
                observed_count: ($matched | length),
                expected_count: $check.minimum,
                matched_terms: $matched
              }
          elif $check.kind == "minimum_grounded_findings" then
            ([bullet_lines[]
              | select(
                  has_context($context_terms)
                  and test("(?i)\\b(because|why|rationale|reason)\\b")
                  and test("(?i)\\b(alternative|instead|recommend|should)\\b")
                )]) as $matched
            | {
                id: $check.id,
                kind: $check.kind,
                status: pass_if(($matched | length) >= $check.minimum),
                observed_count: ($matched | length),
                expected_count: $check.minimum,
                required_components: $check.required_components
              }
          elif $check.kind == "forbid_regex" then
            ([$check.patterns[] as $pattern
              | select(try ($response | test($pattern)) catch false)
              | $pattern]) as $matched
            | {
                id: $check.id,
                kind: $check.kind,
                status: pass_if(($matched | length) == 0),
                observed_count: ($matched | length),
                expected_count: 0,
                matched_pattern_count: ($matched | length)
              }
          else
            {
              id: $check.id,
              kind: $check.kind,
              status: "failed",
              observed_count: 0,
              expected_count: 0
            }
          end
      ]) as $checks
      | {
          status: (if all($checks[]; .status == "passed")
            then "passed" else "failed" end),
          checks: $checks
        }
    '
}

judge_error_category() {
  case "$1" in
    candidate_response_unavailable|candidate_response_too_large|judge_response_malformed|judge_score_invalid)
      printf '%s\n' 'response'
      ;;
    judge_credentials_rejected)
      printf '%s\n' 'credentials'
      ;;
    judge_model_unavailable)
      printf '%s\n' 'model'
      ;;
    judge_request_parameters_unsupported)
      printf '%s\n' 'configuration'
      ;;
    judge_provider_endpoint_unavailable)
      printf '%s\n' 'provider'
      ;;
    judge_request_timeout|judge_provider_transport_error)
      printf '%s\n' 'transport'
      ;;
    judge_redaction_failure)
      printf '%s\n' 'security'
      ;;
    judge_provider_rate_limited|judge_provider_error)
      printf '%s\n' 'provider'
      ;;
    *)
      printf '%s\n' 'provider'
      ;;
  esac
}

build_judge_request() {
  local candidate_text="$1"
  local request_file="$2"

  jq -n \
    --arg model "$JUDGE_MODEL" \
    --rawfile task "$TASK_FILE" \
    --rawfile rubric "$RUBRIC_FILE" \
    --arg candidate "$candidate_text" \
    --arg reasoning_effort "$JUDGE_REASONING_EFFORT" \
    --argjson max_tokens "$JUDGE_MAX_TOKENS" \
    --argjson stream "$REQUEST_STREAM" \
    --argjson provider "$REQUEST_PROVIDER_JSON" \
    ' {
      model: $model,
      messages: [
        {
          role: "system",
          content: (
            "You are an independent rubric judge. Score one anonymized candidate " +
            "response against the supplied task and fixed rubric. Do not infer or " +
            "mention the target model, condition, or any other response. Return " +
            "only a JSON object with exactly score and evidence. score must be an " +
            "integer from 0 through 100. evidence must contain at most three " +
            "short strings of at most 512 characters and must not contain secrets, " +
            "authorization headers, or raw provider logs."
          )
        },
        {
          role: "user",
          content: (
            "TASK:\n" + $task +
            "\n\nRUBRIC:\n" + $rubric +
            "\n\nANONYMIZED CANDIDATE RESPONSE:\n" + $candidate
          )
        }
      ],
      max_tokens: $max_tokens,
      reasoning: {effort: $reasoning_effort},
      stream: $stream,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "api_paired_judgment",
          strict: true,
          schema: {
            type: "object",
            properties: {
              score: {type: "integer"},
              evidence: {type: "array", items: {type: "string"}}
            },
            required: ["score", "evidence"],
            additionalProperties: false
          }
        }
      },
      provider: $provider
    } ' >"$request_file"
}

normalize_judge_payload() {
  sed \
    -e '1{/^[[:space:]]*```json[[:space:]]*$/d;}' \
    -e '${/^[[:space:]]*```[[:space:]]*$/d;}'
}

JUDGE_RESULT=""
JUDGE_FAILED="false"
JUDGE_SCORE=""

judge_candidate() {
  local candidate_text="$1"
  local candidate_available="$2"
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
  local error_message_value=""
  local provider_error_type=""
  local response_shape_json="null"
  local resolved_model=""
  local resolution_status="not-reported"
  local usage_json="null"
  local router_metadata_json="null"
  local finish_reason=""
  local request_hash=""
  local response_text=""
  local normalized_payload=""
  local parsed_score="null"
  local parsed_evidence='[]'
  local status="failed"
  local outcome="not-scored"
  local started_at
  local ended_at
  local duration_seconds
  local candidate_bytes=""
  local evidence
  local secret_evidence="false"

  JUDGE_RESULT=""
  JUDGE_FAILED="false"
  JUDGE_SCORE=""

  if [ "$candidate_available" != "true" ]; then
    JUDGE_FAILED="true"
    JUDGE_RESULT="$(jq -n \
      --arg model "$JUDGE_MODEL" \
      --argjson request "$JUDGE_REQUEST_JSON" \
      ' {
        status: "not_run",
        outcome: "not-scored",
        requested_model: $model,
        request: $request,
        score: null,
        evidence: [],
        timing: {duration_seconds: 0},
        error: {
          type: "infrastructure",
          category: "response",
          code: "candidate_response_unavailable",
          message: "The candidate response was not available for blind judging."
        }
      } ')"
    return
  fi

  candidate_bytes="$(printf '%s' "$candidate_text" | wc -c | tr -d ' ')"
  if [ "$candidate_bytes" -gt 16384 ]; then
    JUDGE_FAILED="true"
    JUDGE_RESULT="$(jq -n \
      --arg model "$JUDGE_MODEL" \
      --argjson request "$JUDGE_REQUEST_JSON" \
      ' {
        status: "failed",
        outcome: "not-scored",
        requested_model: $model,
        request: $request,
        score: null,
        evidence: [],
        timing: {duration_seconds: 0},
        error: {
          type: "infrastructure",
          category: "response",
          code: "candidate_response_too_large",
          message: "The candidate response exceeded the bounded judge input."
        }
      } ')"
    return
  fi

  REQUEST_INDEX=$((REQUEST_INDEX + 1))
  request_file="$TEMP_DIR/request-$REQUEST_INDEX.json"
  response_file="$TEMP_DIR/response-$REQUEST_INDEX.json"
  stderr_file="$TEMP_DIR/stderr-$REQUEST_INDEX.txt"
  http_status_file="$TEMP_DIR/status-$REQUEST_INDEX.txt"
  started_at="$(now_seconds)"

  build_judge_request "$candidate_text" "$request_file"
  request_hash="$(sha256_file "$request_file")"

  set +e
  "$CURL_BIN" \
    --silent \
    --show-error \
    --connect-timeout "$REQUEST_TIMEOUT_SECONDS" \
    --max-time "$REQUEST_TIMEOUT_SECONDS" \
    --request POST \
    --header "Authorization: Bearer $OPENROUTER_API_KEY" \
    --header 'X-OpenRouter-Metadata: enabled' \
    --header 'Content-Type: application/json' \
    --data-binary "@$request_file" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "${ROUTING_BASE_URL%/}$REQUEST_ENDPOINT" \
    >"$http_status_file" \
    2>"$stderr_file"
  curl_exit=$?
  set -e

  ended_at="$(now_seconds)"
  duration_seconds=$((ended_at - started_at))
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
      error_code="judge_request_timeout"
    else
      error_code="judge_provider_transport_error"
    fi
  elif ! [[ "$http_status" =~ ^[0-9]{3}$ ]]; then
    error_code="judge_provider_transport_error"
  elif [[ ! "$http_status" =~ ^2[0-9]{2}$ ]]; then
    case "$(classify_response_error "$http_status" "$response_file")" in
      credentials_rejected) error_code="judge_credentials_rejected" ;;
      model_unavailable) error_code="judge_model_unavailable" ;;
      request_parameters_unsupported) error_code="judge_request_parameters_unsupported" ;;
      provider_endpoint_unavailable) error_code="judge_provider_endpoint_unavailable" ;;
      request_timeout) error_code="judge_request_timeout" ;;
      provider_rate_limited) error_code="judge_provider_rate_limited" ;;
      *) error_code="judge_provider_error" ;;
    esac
  elif [ "$response_state" != "valid_json" ]; then
    error_code="judge_response_malformed"
  else
    error_code="$(classify_response_error "$http_status" "$response_file")"
    if [ -n "$error_code" ]; then
      error_code="judge_response_malformed"
    fi
  fi

  if [ "$response_state" = "valid_json" ]; then
    provider_error_type="$(extract_provider_error_type "$response_file")"
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
    router_metadata_json="$(extract_router_metadata "$response_file")"
    response_shape_json="$(extract_response_shape "$response_file")"
  fi

  if [ -z "$error_code" ]; then
    response_text="$(jq -r '.choices[0].message.content' "$response_file" 2>/dev/null || true)"
    normalized_payload="$(printf '%s\n' "$response_text" | normalize_judge_payload)"
    if ! jq -e . <<<"$normalized_payload" >/dev/null 2>&1; then
      error_code="judge_response_malformed"
    elif ! jq -e '
      type == "object"
      and (keys | sort == ["evidence", "score"])
      and (.score | type == "number" and floor == . and . >= 0 and . <= 100)
      and (.evidence | type == "array" and length >= 1 and length <= 3)
      and ([.evidence[] |
        if type != "string" then false
        else
          ((gsub("[[:space:]]+"; " ")
            | gsub("^[[:space:]]+|[[:space:]]+$"; "")
            | length) > 0)
          and (length <= 512)
        end
      ] | all)
    ' <<<"$normalized_payload" >/dev/null 2>&1; then
      error_code="judge_score_invalid"
    else
      parsed_score="$(jq -c '.score' <<<"$normalized_payload")"
      parsed_evidence="$(jq -c '
        .evidence
        | map(gsub("[[:space:]]+"; " ")
          | gsub("^[[:space:]]+|[[:space:]]+$"; ""))
      ' <<<"$normalized_payload")"
      while IFS= read -r evidence; do
        if printf '%s' "$evidence" | grep -Eqi \
          '(OPENROUTER_API_KEY|AUTHORIZATION|BEARER[[:space:]]+[A-Za-z0-9._~+/=-]{8,}|(sk|pk)-[A-Za-z0-9_-]{12,})'; then
          secret_evidence="true"
        fi
      done < <(jq -r '.[]' <<<"$parsed_evidence")
      if [ "$secret_evidence" = "true" ]; then
        error_code="judge_redaction_failure"
        parsed_score="null"
        parsed_evidence='[]'
      fi
    fi
  fi

  if [ -n "$error_code" ]; then
    error_category_value="$(judge_error_category "$error_code")"
    error_message_value="$(describe_error "$error_code")"
  else
    status="scored"
    outcome="scored"
    JUDGE_SCORE="$parsed_score"
  fi

  JUDGE_FAILED="false"
  if [ -n "$error_code" ]; then
    JUDGE_FAILED="true"
  fi

  JUDGE_RESULT="$(jq -n \
    --arg model "$JUDGE_MODEL" \
    --arg status "$status" \
    --arg outcome "$outcome" \
    --arg request_hash "$request_hash" \
    --arg http_status "$http_status" \
    --arg response_state "$response_state" \
    --arg resolved_model "$resolved_model" \
    --arg resolution_status "$resolution_status" \
    --arg finish_reason "$finish_reason" \
    --arg stderr_category "$stderr_category" \
    --arg stderr_fingerprint "$stderr_fingerprint" \
    --arg response_fingerprint "$response_fingerprint" \
    --arg error_code "$error_code" \
    --arg error_category "$error_category_value" \
    --arg error_message "$error_message_value" \
    --arg provider_error_type "$provider_error_type" \
    --argjson request "$JUDGE_REQUEST_JSON" \
    --argjson curl_exit "$curl_exit" \
    --argjson usage "$usage_json" \
    --argjson router_metadata "$router_metadata_json" \
    --argjson response_shape "$response_shape_json" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson score "$parsed_score" \
    --argjson evidence "$parsed_evidence" \
    ' {
      status: $status,
      outcome: $outcome,
      requested_model: $model,
      request: $request,
      request_sha256: $request_hash,
      response: {
        state: $response_state,
        http_status: (if ($http_status | test("^[0-9]{3}$")) then ($http_status | tonumber) else null end),
        curl_exit: $curl_exit,
        resolved_model: (if $resolved_model == "" then null else $resolved_model end),
        resolution_status: $resolution_status,
        finish_reason: (if $finish_reason == "" then null else $finish_reason end),
        usage: $usage,
        router_metadata: $router_metadata,
        shape: $response_shape,
        content: null,
        response_sha256: (if $response_fingerprint == "" then null else $response_fingerprint end)
      },
      timing: {duration_seconds: $duration_seconds},
      score: $score,
      evidence: $evidence
    }
    + (if $error_code == "" then {}
       else {
         error: {
           type: "infrastructure",
           category: $error_category,
           code: $error_code,
           message: (if $error_message == ""
             then "The judge request did not produce a bounded score."
             else $error_message
             end),
           diagnostics: {
             response_state: $response_state,
             stderr_category: $stderr_category,
             stderr_sha256: (if $stderr_fingerprint == "" then null else $stderr_fingerprint end),
             provider_error_type: (if $provider_error_type == "" then null else $provider_error_type end),
             response_shape: $response_shape
           }
         }
       }
       end) ' )"
}

CONDITION_RESULT=""
CONDITION_FAILED="false"
CONDITION_RESPONSE_TEXT=""
CONDITION_RESPONSE_AVAILABLE="false"

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
  local error_message_value=""
  local provider_error_type=""
  local resolved_model=""
  local resolution_status="not-reported"
  local usage_json="null"
  local router_metadata_json="null"
  local finish_reason=""
  local request_hash
  local started_at
  local ended_at
  local duration_seconds

  CONDITION_RESPONSE_TEXT=""
  CONDITION_RESPONSE_AVAILABLE="false"
  REQUEST_INDEX=$((REQUEST_INDEX + 1))
  request_file="$TEMP_DIR/request-$REQUEST_INDEX.json"
  response_file="$TEMP_DIR/response-$REQUEST_INDEX.json"
  stderr_file="$TEMP_DIR/stderr-$REQUEST_INDEX.txt"
  http_status_file="$TEMP_DIR/status-$REQUEST_INDEX.txt"
  started_at="$(now_seconds)"

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
    --header 'X-OpenRouter-Metadata: enabled' \
    --header 'Content-Type: application/json' \
    --data-binary "@$request_file" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "${ROUTING_BASE_URL%/}$REQUEST_ENDPOINT" \
    >"$http_status_file" \
    2>"$stderr_file"
  curl_exit=$?
  set -e
  ended_at="$(now_seconds)"
  duration_seconds=$((ended_at - started_at))

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
    provider_error_type="$(extract_provider_error_type "$response_file")"
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
    router_metadata_json="$(extract_router_metadata "$response_file")"
    if [ -z "$error_code" ]; then
      CONDITION_RESPONSE_TEXT="$(jq -r '.choices[0].message.content' \
        "$response_file" 2>/dev/null || true)"
      CONDITION_RESPONSE_AVAILABLE="true"
    fi
  fi

  CONDITION_FAILED="false"
  if [ -n "$error_code" ]; then
    CONDITION_FAILED="true"
    error_category_value="$(error_category "$error_code")"
    error_message_value="$(describe_error "$error_code")"
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
    --arg error_message "$error_message_value" \
    --arg provider_error_type "$provider_error_type" \
    --arg http_status "$http_status" \
    --arg response_state "$response_state" \
    --arg resolved_model "$resolved_model" \
    --arg resolution_status "$resolution_status" \
    --arg finish_reason "$finish_reason" \
    --arg stderr_category "$stderr_category" \
    --arg stderr_fingerprint "$stderr_fingerprint" \
    --arg response_fingerprint "$response_fingerprint" \
    --argjson request "$REQUEST_JSON" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson curl_exit "$curl_exit" \
    --argjson usage "$usage_json" \
    --argjson router_metadata "$router_metadata_json" \
    '{
      condition: $condition,
      requested_model: $model,
      status: $status,
      outcome: "not-scored",
      request_count: 1,
      request: $request,
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
        router_metadata: $router_metadata,
        content: null,
        response_sha256: (if $response_fingerprint == "" then null else $response_fingerprint end)
      },
      timing: {duration_seconds: $duration_seconds}
    }
    + (if $error_code == "" then {}
       else {
         error: {
           type: "infrastructure",
           category: $error_category,
           code: $error_code,
           message: (if $error_message == ""
             then "The provider request did not produce a valid model response."
             else $error_message
             end),
           diagnostics: {
             response_state: $response_state,
             stderr_category: $stderr_category,
             stderr_sha256: (if $stderr_fingerprint == "" then null else $stderr_fingerprint end),
             provider_error_type: (if $provider_error_type == "" then null else $provider_error_type end)
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
    --task-revision)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --task-revision requires a value" >&2; exit 2; }
      TASK_REVISION="$2"
      shift 2
      ;;
    --skill-file)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --skill-file requires a path" >&2; exit 2; }
      SKILL_FILE="$2"
      shift 2
      ;;
    --skill-revision)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --skill-revision requires a value" >&2; exit 2; }
      SKILL_REVISION="$2"
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
    --rubric-file)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --rubric-file requires a path" >&2; exit 2; }
      RUBRIC_FILE="$2"
      shift 2
      ;;
    --rubric-revision)
      [ "$#" -ge 2 ] || { echo "api paired evaluation: --rubric-revision requires a value" >&2; exit 2; }
      RUBRIC_REVISION="$2"
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
[ -n "$TASK_REVISION" ] || write_failure "configuration" "task_revision_missing" "task_revision" \
  "the task fixture revision must be provided."
[ -s "$SKILL_FILE" ] || write_failure "configuration" "skill_fixture_invalid" "skill_file" \
  "the selected skill fixture must be a non-empty file."
[ -n "$SKILL_REVISION" ] || write_failure "configuration" "skill_revision_missing" "skill_revision" \
  "the selected skill revision must be provided."
[ -n "$FIXTURE_REVISION" ] || write_failure "configuration" "fixture_revision_missing" "fixture_revision" \
  "the fixture revision must be provided."
[ -s "$RUBRIC_FILE" ] || write_failure "configuration" "rubric_fixture_invalid" "rubric_file" \
  "the fixed rubric must be a non-empty file."
[ -n "$RUBRIC_REVISION" ] || write_failure "configuration" "rubric_revision_missing" "rubric_revision" \
  "the rubric revision must be provided."
if [[ "$FIXTURE_REVISION" == *$'\n'* || "$TASK_REVISION" == *$'\n'* \
  || "$SKILL_REVISION" == *$'\n'* || "$SKILL_NAME" == *$'\n'* \
  || "$RUBRIC_REVISION" == *$'\n'* ]]; then
  write_failure "configuration" "fixture_metadata_malformed" "fixture" \
    "fixture metadata must not contain newlines."
fi
[ -n "$SKILL_NAME" ] || SKILL_NAME="$(basename "$(dirname "$SKILL_FILE")")"
[ -n "$SKILL_NAME" ] || write_failure "configuration" "skill_name_missing" "skill_name" \
  "the selected skill must have a stable name."

if ! jq -e \
  --arg rubric_revision "$RUBRIC_REVISION" '
    .schema_version == 1
    and (.rubric_id | type == "string" and length > 0)
    and .revision == $rubric_revision
    and (.checks | type == "array" and length > 0)
    and ([.checks[].id | type == "string" and length > 0] | all)
    and ([.checks[].id] | length == (unique | length))
    and ([.checks[] | .bounded == true and .field == "response_text"] | all)
    and ([.checks[].kind
      | select(. != "required_headings"
        and . != "minimum_context_references"
        and . != "minimum_grounded_findings"
        and . != "forbid_regex")] | length == 0)
    and any(.checks[]; .kind == "required_headings"
      and (.headings | type == "array" and length > 0))
    and any(.checks[]; .kind == "minimum_context_references"
      and (.terms | type == "array" and length > 0)
      and (.minimum | type == "number" and . >= 1))
    and any(.checks[]; .kind == "minimum_grounded_findings"
      and (.minimum | type == "number" and . >= 1)
      and .per_item == true)
    and any(.checks[]; .kind == "forbid_regex"
      and (.patterns | type == "array" and length > 0)
      and (.regression_phrases | type == "array" and length > 0))
  ' "$RUBRIC_FILE" >/dev/null 2>&1; then
  write_failure "configuration" "rubric_invalid" "rubric_file" \
    "the rubric must be a fixed bounded response-level contract."
fi

MAX_ARTIFACT_BYTES=65536

if ! jq -e '
  . as $profile
  | .schema_version == 1
  and
  .status == "valid"
  and .result_type == "profile"
  and (.target_models | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
  and (.judge_model | type == "string" and length > 0)
  and (any($profile.target_models[]; . == $profile.judge_model) | not)
  and .provider_routing.provider == "openrouter"
  and .provider_routing.gateway == "openrouter-chat-completions"
  and (.provider_routing.base_url | test("^https://openrouter\\.ai/api/v1/?$"))
  and .provider_routing.allow_fallbacks == false
  and .provider_routing.require_parameters == true
  and .request.method == "POST"
  and .request.endpoint == "/chat/completions"
  and .request.temperature == null
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
REQUEST_METHOD="$(jq -r '.request.method' "$PROFILE_PATH")"
REQUEST_ENDPOINT="$(jq -r '.request.endpoint' "$PROFILE_PATH")"
REQUEST_MAX_TOKENS="$(jq -r '.request.max_tokens' "$PROFILE_PATH")"
REQUEST_STREAM="$(jq -r '.request.stream' "$PROFILE_PATH")"
REQUEST_MAX_TURNS="$(jq -r '.request.max_turns' "$PROFILE_PATH")"
REQUEST_TIMEOUT_SECONDS="$(jq -r '.request.timeout_seconds' "$PROFILE_PATH")"
REQUEST_PROVIDER_JSON="$(jq -c '{
  allow_fallbacks: .provider_routing.allow_fallbacks,
  require_parameters: .provider_routing.require_parameters
}' "$PROFILE_PATH")"
JUDGE_REQUEST_JSON="$(jq -n \
  --arg method "$REQUEST_METHOD" \
  --arg endpoint "$REQUEST_ENDPOINT" \
  --arg reasoning_effort "$JUDGE_REASONING_EFFORT" \
  --argjson max_tokens "$JUDGE_MAX_TOKENS" \
  --argjson stream "$REQUEST_STREAM" \
  --argjson max_turns "$REQUEST_MAX_TURNS" \
  --argjson timeout_seconds "$REQUEST_TIMEOUT_SECONDS" \
  '{
    method: $method,
    endpoint: $endpoint,
    temperature: null,
    max_tokens: $max_tokens,
    reasoning: {effort: $reasoning_effort},
    stream: $stream,
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "api_paired_judgment",
        strict: true,
        schema: {
          type: "object",
          properties: {
            score: {type: "integer"},
            evidence: {type: "array", items: {type: "string"}}
          },
          required: ["score", "evidence"],
          additionalProperties: false
        }
      }
    },
    max_turns: $max_turns,
    timeout_seconds: $timeout_seconds
  }')"

TASK_HASH="$(sha256_file "$TASK_FILE")"
SKILL_HASH="$(sha256_file "$SKILL_FILE")"
RUBRIC_HASH="$(sha256_file "$RUBRIC_FILE")"

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  write_failure "credentials" "credential_missing" "OPENROUTER_API_KEY" \
    "the OpenRouter credential is required for model-backed execution."
fi

PAIRS_NDJSON="$TEMP_DIR/pairs.ndjson"
OVERALL_FAILURE="false"
TARGET_COUNT="${#TARGET_MODELS[@]}"
TOTAL_REQUEST_COUNT=$((TARGET_COUNT * 4))
COMPLETED_PAIR_COUNT=0
FAILED_PAIR_COUNT=0

progress \
  "run_started targets=$TARGET_COUNT" \
  "requests=$TOTAL_REQUEST_COUNT" \
  "judge=$JUDGE_MODEL" \
  "timeout=${REQUEST_TIMEOUT_SECONDS}s"

target_index=0
for model in "${TARGET_MODELS[@]}"; do
  target_index=$((target_index + 1))
  progress \
    "target=$target_index/$TARGET_COUNT" \
    "model=$model" \
    "phase=target" \
    "status=running"

  progress \
    "target=$target_index/$TARGET_COUNT" \
    "model=$model" \
    "phase=treatment" \
    "status=running" \
    "request=$((REQUEST_INDEX + 1))/$TOTAL_REQUEST_COUNT"
  process_condition "$model" "treatment"
  treatment_result="$CONDITION_RESULT"
  treatment_failed="$CONDITION_FAILED"
  treatment_response_text="$CONDITION_RESPONSE_TEXT"
  treatment_response_available="$CONDITION_RESPONSE_AVAILABLE"
  report_result "$target_index" "$TARGET_COUNT" "$model" "treatment" "$treatment_result"
  if [ "$treatment_response_available" = "true" ]; then
    treatment_deterministic="$(evaluate_deterministic "$treatment_response_text")"
  else
    treatment_deterministic="$(jq -n '{
      status: "not_run",
      checks: [],
      error: {
        type: "infrastructure",
        category: "response",
        code: "candidate_response_unavailable",
        message: "Deterministic checks could not inspect the candidate response."
      }
    }')"
  fi

  progress \
    "target=$target_index/$TARGET_COUNT" \
    "model=$model" \
    "phase=control" \
    "status=running" \
    "request=$((REQUEST_INDEX + 1))/$TOTAL_REQUEST_COUNT"
  process_condition "$model" "control"
  control_result="$CONDITION_RESULT"
  control_failed="$CONDITION_FAILED"
  control_response_text="$CONDITION_RESPONSE_TEXT"
  control_response_available="$CONDITION_RESPONSE_AVAILABLE"
  report_result "$target_index" "$TARGET_COUNT" "$model" "control" "$control_result"
  if [ "$control_response_available" = "true" ]; then
    control_deterministic="$(evaluate_deterministic "$control_response_text")"
  else
    control_deterministic="$(jq -n '{
      status: "not_run",
      checks: [],
      error: {
        type: "infrastructure",
        category: "response",
        code: "candidate_response_unavailable",
        message: "Deterministic checks could not inspect the candidate response."
      }
    }')"
  fi

  if [ "$treatment_response_available" = "true" ]; then
    progress \
      "target=$target_index/$TARGET_COUNT" \
      "model=$model" \
      "phase=treatment-judge" \
      "status=running" \
      "request=$((REQUEST_INDEX + 1))/$TOTAL_REQUEST_COUNT"
  else
    progress \
      "target=$target_index/$TARGET_COUNT" \
      "model=$model" \
      "phase=treatment-judge" \
      "status=skipped" \
      "reason=candidate_response_unavailable"
  fi
  judge_candidate "$treatment_response_text" "$treatment_response_available"
  treatment_judge="$JUDGE_RESULT"
  treatment_judge_failed="$JUDGE_FAILED"
  treatment_score="$JUDGE_SCORE"
  report_result "$target_index" "$TARGET_COUNT" "$model" "treatment-judge" "$treatment_judge"

  if [ "$control_response_available" = "true" ]; then
    progress \
      "target=$target_index/$TARGET_COUNT" \
      "model=$model" \
      "phase=control-judge" \
      "status=running" \
      "request=$((REQUEST_INDEX + 1))/$TOTAL_REQUEST_COUNT"
  else
    progress \
      "target=$target_index/$TARGET_COUNT" \
      "model=$model" \
      "phase=control-judge" \
      "status=skipped" \
      "reason=candidate_response_unavailable"
  fi
  judge_candidate "$control_response_text" "$control_response_available"
  control_judge="$JUDGE_RESULT"
  control_judge_failed="$JUDGE_FAILED"
  control_score="$JUDGE_SCORE"
  report_result "$target_index" "$TARGET_COUNT" "$model" "control-judge" "$control_judge"

  treatment_result="$(jq -n \
    --argjson candidate "$treatment_result" \
    --argjson deterministic "$treatment_deterministic" \
    --argjson judge "$treatment_judge" \
    '$candidate + {deterministic: $deterministic, judge: $judge}')"
  control_result="$(jq -n \
    --argjson candidate "$control_result" \
    --argjson deterministic "$control_deterministic" \
    --argjson judge "$control_judge" \
    '$candidate + {deterministic: $deterministic, judge: $judge}')"

  pair_status="completed"
  if [ "$treatment_failed" = "true" ] || [ "$control_failed" = "true" ] \
    || [ "$treatment_judge_failed" = "true" ] \
    || [ "$control_judge_failed" = "true" ]; then
    pair_status="failed"
    OVERALL_FAILURE="true"
    FAILED_PAIR_COUNT=$((FAILED_PAIR_COUNT + 1))
  else
    COMPLETED_PAIR_COUNT=$((COMPLETED_PAIR_COUNT + 1))
  fi

  pair_outcome="scored"
  if [ "$pair_status" != "completed" ]; then
    pair_outcome="not-scored"
  fi

  if [ "$treatment_judge_failed" = "true" ] \
    || [ "$control_judge_failed" = "true" ] \
    || [ -z "$treatment_score" ] || [ -z "$control_score" ]; then
    paired_lift="$(jq -n '{
      status: "not-scored",
      treatment_score: null,
      control_score: null,
      treatment_minus_control: null
    }')"
  else
    paired_lift="$(jq -n \
      --argjson treatment_score "$treatment_score" \
      --argjson control_score "$control_score" \
      '{
        status: "scored",
        score_scale: {min: 0, max: 100},
        treatment_score: $treatment_score,
        control_score: $control_score,
        treatment_minus_control: ($treatment_score - $control_score)
    }')"
  fi

  progress \
    "target=$target_index/$TARGET_COUNT" \
    "model=$model" \
    "phase=pair" \
    "status=$pair_status" \
    "outcome=$pair_outcome"

  jq -n \
    --arg model "$model" \
    --arg fixture_revision "$FIXTURE_REVISION" \
    --arg task_revision "$TASK_REVISION" \
    --arg skill_revision "$SKILL_REVISION" \
    --arg rubric_revision "$RUBRIC_REVISION" \
    --arg skill_name "$SKILL_NAME" \
    --arg task_hash "$TASK_HASH" \
    --arg skill_hash "$SKILL_HASH" \
    --arg rubric_hash "$RUBRIC_HASH" \
    --arg pair_status "$pair_status" \
    --arg pair_outcome "$pair_outcome" \
    --argjson request "$REQUEST_JSON" \
    --argjson routing "$ROUTING_JSON" \
    --argjson treatment "$treatment_result" \
    --argjson control "$control_result" \
    --argjson paired_lift "$paired_lift" \
    '{
      target_model: $model,
      fixture_revision: $fixture_revision,
      task_revision: $task_revision,
      skill_revision: $skill_revision,
      rubric_revision: $rubric_revision,
      skill_name: $skill_name,
      task_sha256: $task_hash,
      skill_sha256: $skill_hash,
      rubric_sha256: $rubric_hash,
      request: $request,
      provider_routing: $routing,
      status: $pair_status,
      outcome: $pair_outcome,
      treatment: $treatment,
      control: $control,
      paired_lift: $paired_lift
    }' >>"$PAIRS_NDJSON"
done

PAIRS_JSON="$(jq -s . "$PAIRS_NDJSON")"
OVERALL_STATUS="completed"
if [ "$OVERALL_FAILURE" = "true" ]; then
  OVERALL_STATUS="failed"
fi
OVERALL_OUTCOME="scored"
if [ "$OVERALL_FAILURE" = "true" ]; then
  OVERALL_OUTCOME="not-scored"
fi

jq -n \
  --arg schema_version "$PROFILE_SCHEMA_VERSION" \
  --arg profile "$PROFILE_NAME" \
  --arg status "$OVERALL_STATUS" \
  --arg outcome "$OVERALL_OUTCOME" \
  --arg fixture_revision "$FIXTURE_REVISION" \
  --arg task_revision "$TASK_REVISION" \
  --arg skill_revision "$SKILL_REVISION" \
  --arg rubric_revision "$RUBRIC_REVISION" \
  --arg skill_name "$SKILL_NAME" \
  --arg task_hash "$TASK_HASH" \
  --arg skill_hash "$SKILL_HASH" \
  --arg rubric_hash "$RUBRIC_HASH" \
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
    outcome: $outcome,
    profile: {name: $profile},
    fixture: {
      revision: $fixture_revision,
      task_revision: $task_revision,
      skill_revision: $skill_revision,
      rubric_revision: $rubric_revision,
      skill_name: $skill_name,
      task_sha256: $task_hash,
      skill_sha256: $skill_hash,
      rubric_sha256: $rubric_hash
    },
    target_models: $target_models,
    judge_model: $judge_model,
    provider_routing: $routing,
    request: $request,
    pairs: $pairs
  }' >"$ARTIFACT_DIR/results.json"

artifact_bytes="$(wc -c <"$ARTIFACT_DIR/results.json" | tr -d ' ')"
if [ "$artifact_bytes" -gt "$MAX_ARTIFACT_BYTES" ]; then
  write_failure "security" "artifact_too_large" "results.json" \
    "the normalized result exceeded the bounded artifact policy (bytes=$artifact_bytes max_bytes=$MAX_ARTIFACT_BYTES)."
fi

if [ "$OVERALL_FAILURE" = "true" ]; then
  progress \
    "run_finished status=$OVERALL_STATUS" \
    "outcome=$OVERALL_OUTCOME" \
    "targets=$TARGET_COUNT" \
    "completed_pairs=$COMPLETED_PAIR_COUNT" \
    "failed_pairs=$FAILED_PAIR_COUNT" \
    "requests=$REQUEST_INDEX"
  failure_annotation='::error title=API paired evaluation failed::'
  failure_annotation+='inspect per-request progress and the normalized results artifact '
  failure_annotation+='for typed failure codes.'
  printf '%s\n' "$failure_annotation" >&2
  echo "API paired evaluation failed: $ARTIFACT_DIR/results.json" >&2
  exit 1
fi

progress \
  "run_finished status=$OVERALL_STATUS" \
  "outcome=$OVERALL_OUTCOME" \
  "targets=$TARGET_COUNT" \
  "completed_pairs=$COMPLETED_PAIR_COUNT" \
  "failed_pairs=$FAILED_PAIR_COUNT" \
  "requests=$REQUEST_INDEX"
echo "API paired evaluation completed: $ARTIFACT_DIR/results.json"
