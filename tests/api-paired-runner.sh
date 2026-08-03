#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$ROOT_DIR/evals/api-evaluation-profile.sh"
RUNNER="$ROOT_DIR/evals/run-api-paired.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "api paired runner check failed: $*" >&2
  exit 1
}

FAKE_CURL="$TEMP_DIR/curl"
REQUEST_LOG="$TEMP_DIR/requests.ndjson"
TASK_FILE="$TEMP_DIR/task.txt"
SKILL_FILE="$TEMP_DIR/SKILL.md"
PROFILE_FILE="$TEMP_DIR/profile.json"
ARTIFACT_DIR="$TEMP_DIR/artifacts"

cat >"$FAKE_CURL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

request_file=""
output_file=""
request_method=""
request_url=""
has_auth_header="false"
has_content_type="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-binary)
      request_file="${2#@}"
      shift 2
      ;;
    --output)
      output_file="$2"
      shift 2
      ;;
    --request)
      request_method="$2"
      shift 2
      ;;
    --header)
      case "$2" in
        Authorization:\ Bearer\ *) has_auth_header="true" ;;
        Content-Type:\ application/json) has_content_type="true" ;;
      esac
      shift 2
      ;;
    --write-out|--connect-timeout|--max-time)
      shift 2
      ;;
    --location)
      echo "runner must not follow redirects" >&2
      exit 50
      ;;
    --silent|--show-error)
      shift
      ;;
    *)
      request_url="$1"
      shift
      ;;
  esac
done

[ -n "$request_file" ] || { echo "missing request body" >&2; exit 40; }
[ -f "$request_file" ] || { echo "request body does not exist" >&2; exit 41; }
[ -n "$output_file" ] || { echo "missing response output" >&2; exit 42; }
[ "$request_method" = "POST" ] || { echo "request must use POST" >&2; exit 43; }
[ "$request_url" = "https://openrouter.ai/api/v1/chat/completions" ] \
  || { echo "request must use the OpenRouter chat endpoint" >&2; exit 44; }
[ "$has_auth_header" = "true" ] || { echo "request must contain authorization" >&2; exit 45; }
[ "$has_content_type" = "true" ] || { echo "request must declare JSON" >&2; exit 46; }
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "missing mock credential" >&2; exit 47; }

jq -c --arg url "$request_url" '
  {
    url: $url,
    model,
    messages,
    temperature,
    max_tokens,
    stream,
    provider
  }
' "$request_file" >>"$REQUEST_LOG"

model="$(jq -r '.model' "$request_file")"
jq -e '
  .provider.allow_fallbacks == false
  and .provider.require_parameters == true
' "$request_file" >/dev/null || { echo "request must preserve provider routing" >&2; exit 48; }

case "$MOCK_CURL_MODE" in
  success)
    jq -n --arg model "$model" '{
      id: "mock-response",
      model: $model,
      choices: [{
        index: 0,
        message: {role: "assistant", content: "mock response"},
        finish_reason: "stop"
      }],
      usage: {prompt_tokens: 11, completion_tokens: 4, total_tokens: 15}
    }' >"$output_file"
    printf '%s' '200'
    ;;
  model-unavailable)
    : >"$output_file"
    printf '%s' '404'
    ;;
  redirect)
    : >"$output_file"
    printf '%s' '302'
    ;;
  credentials-rejected)
    : >"$output_file"
    printf '%s' '401'
    ;;
  rate-limited)
    : >"$output_file"
    printf '%s' '429'
    ;;
  provider-error)
    printf '%s' 'provider-only-secret' >"$output_file"
    printf '%s' '500'
    ;;
  timeout)
    printf '%s\n' 'curl: (28) Operation timed out' >&2
    exit 28
    ;;
  malformed)
    printf '%s' 'body-only-secret' >"$output_file"
    printf '%s' '200'
    ;;
  *)
    echo "unsupported mock mode" >&2
    exit 49
    ;;
esac
EOF
chmod +x "$FAKE_CURL"

printf '%s\n' 'Audit the project instructions and report grounded risks.' >"$TASK_FILE"
printf '%s\n' 'SKILL-CONTEXT: audit project instructions without inventing state.' >"$SKILL_FILE"

"$PROFILE" \
  --target-models 'openai/test-one,google/test-two' \
  --judge-model 'anthropic/test-judge' \
  --output "$PROFILE_FILE"

set +e
OPENROUTER_API_KEY='test-api-key' \
  CURL_BIN="$FAKE_CURL" \
  MOCK_CURL_MODE='success' \
  REQUEST_LOG="$REQUEST_LOG" \
  "$RUNNER" \
  --profile "$PROFILE_FILE" \
  --task-file "$TASK_FILE" \
  --skill-file "$SKILL_FILE" \
  --skill-name agents-md \
  --fixture-revision fixture-v1 \
  --artifact-dir "$ARTIFACT_DIR"
runner_exit=$?
set -e
[ "$runner_exit" -eq 0 ] || {
  jq . "$ARTIFACT_DIR/results.json" >&2
  fail "success mock run must exit zero"
}

RESULTS="$ARTIFACT_DIR/results.json"
[ -f "$RESULTS" ] || fail "paired results were not written"
jq -e '
  .schema_version == 1
  and .suite == "api-skill-utility"
  and .runner == "openrouter-one-turn-paired"
  and .status == "completed"
  and .outcome == "not-scored"
  and .target_models == ["openai/test-one", "google/test-two"]
  and .judge_model == "anthropic/test-judge"
  and .fixture.revision == "fixture-v1"
  and .fixture.skill_name == "agents-md"
  and (.fixture.task_sha256 | startswith("sha256:"))
  and (.fixture.skill_sha256 | startswith("sha256:"))
  and (.pairs | length == 2)
  and ([.pairs[].status] | all(. == "completed"))
  and ([.pairs[].outcome] | all(. == "not-scored"))
  and ([.pairs[].treatment.condition] | unique == ["treatment"])
  and ([.pairs[].control.condition] | unique == ["control"])
  and ([.pairs[].treatment.request_count, .pairs[].control.request_count] | all(. == 1))
  and ([.pairs[].treatment.skill_context] | all(. == "present"))
  and ([.pairs[].control.skill_context] | all(. == "absent"))
  and (([.pairs[] | .treatment.task_sha256, .control.task_sha256] | unique)
    == [.fixture.task_sha256])
  and ([.pairs[].fixture_revision] | unique == ["fixture-v1"])
  and ([.pairs[].treatment.response.resolved_model] == .target_models)
  and ([.pairs[].control.response.resolved_model] == .target_models)
  and ([.pairs[].treatment.response.usage.total_tokens] | all(. == 15))
  and ([.pairs[].control.response.usage.total_tokens] | all(. == 15))
  and ([.pairs[].request.max_turns] | all(. == 1))
  and ([.pairs[].request.stream] | all(. == false))
  and ([.pairs[].provider_routing.gateway] | unique == ["openrouter-chat-completions"])
  and ([.pairs[].provider_routing.allow_fallbacks] | all(. == false))
  and ([.pairs[].treatment.response.content, .pairs[].control.response.content]
    | all(. == null))
' "$RESULTS" >/dev/null || fail "paired results do not satisfy the public contract"

jq -s -e '
  length == 4
  and ([.[].model] | sort == [
    "google/test-two", "google/test-two", "openai/test-one", "openai/test-one"
  ])
  and ([.[].temperature] | unique == [0])
  and ([.[].max_tokens] | unique == [2048])
  and ([.[].stream] | unique == [false])
  and ([.[].provider.allow_fallbacks] | unique == [false])
  and ([.[].provider.require_parameters] | unique == [true])
  and ([.[].url] | unique == ["https://openrouter.ai/api/v1/chat/completions"])
  and (.[0].messages[-1].content == .[1].messages[-1].content)
  and (.[2].messages[-1].content == .[3].messages[-1].content)
  and ([.[0].messages[], .[2].messages[]]
    | map(select(.content | contains("SKILL-CONTEXT"))) | length == 2)
  and ([.[1].messages[], .[3].messages[]]
    | map(select(.content | contains("SKILL-CONTEXT"))) | length == 0)
  and ([.[].messages[] | .content] | all(contains("/agents-md") | not))
' "$REQUEST_LOG" >/dev/null || fail "provider requests do not preserve treatment/control isolation"

PROFILE_WITH_EXTRAS="$TEMP_DIR/profile-with-extras.json"
jq '
  .request += {untrusted_metadata: "profile-only-secret"}
  | .provider_routing += {untrusted_metadata: "routing-only-secret"}
' "$PROFILE_FILE" >"$PROFILE_WITH_EXTRAS"
PROFILE_REDACTION_ARTIFACT="$TEMP_DIR/profile-redaction-artifacts"
PROFILE_REDACTION_LOG="$TEMP_DIR/profile-redaction-requests.ndjson"
set +e
OPENROUTER_API_KEY='test-api-key' \
  CURL_BIN="$FAKE_CURL" \
  MOCK_CURL_MODE='success' \
  REQUEST_LOG="$PROFILE_REDACTION_LOG" \
  "$RUNNER" \
  --profile "$PROFILE_WITH_EXTRAS" \
  --task-file "$TASK_FILE" \
  --skill-file "$SKILL_FILE" \
  --skill-name agents-md \
  --fixture-revision fixture-v1 \
  --artifact-dir "$PROFILE_REDACTION_ARTIFACT" \
  >"$TEMP_DIR/profile-redaction.stdout" \
  2>"$TEMP_DIR/profile-redaction.stderr"
profile_redaction_exit=$?
set -e
[ "$profile_redaction_exit" -eq 0 ] || fail "profile extras must not break a valid run"
jq -e '
  (.request | keys | sort) == [
    "endpoint", "max_tokens", "max_turns", "method", "stream",
    "temperature", "timeout_seconds"
  ]
  and (.provider_routing | keys | sort) == [
    "allow_fallbacks", "base_url", "gateway", "provider",
    "require_parameters"
  ]
  and ((tostring | contains("profile-only-secret")) | not)
  and ((tostring | contains("routing-only-secret")) | not)
' "$PROFILE_REDACTION_ARTIFACT/results.json" >/dev/null \
  || fail "profile extras must not enter durable artifacts"

FAIL_PROFILE="$TEMP_DIR/failure-profile.json"
"$PROFILE" \
  --target-models 'openai/failure-target' \
  --judge-model 'anthropic/failure-judge' \
  --output "$FAIL_PROFILE"

run_provider_failure_case() {
  local case_name="$1"
  local mock_mode="$2"
  local expected_code="$3"
  local expected_category="$4"
  local artifact_dir="$TEMP_DIR/$case_name-artifacts"
  local request_log="$TEMP_DIR/$case_name-requests.ndjson"
  local stdout_file="$TEMP_DIR/$case_name.stdout"
  local stderr_file="$TEMP_DIR/$case_name.stderr"
  local results_file="$artifact_dir/results.json"
  local exit_code

  : >"$request_log"
  set +e
  OPENROUTER_API_KEY='test-api-key' \
    CURL_BIN="$FAKE_CURL" \
    MOCK_CURL_MODE="$mock_mode" \
    REQUEST_LOG="$request_log" \
    "$RUNNER" \
    --profile "$FAIL_PROFILE" \
    --task-file "$TASK_FILE" \
    --skill-file "$SKILL_FILE" \
    --skill-name agents-md \
    --fixture-revision fixture-v1 \
    --artifact-dir "$artifact_dir" \
    >"$stdout_file" 2>"$stderr_file"
  exit_code=$?
  set -e

  [ "$exit_code" -eq 1 ] || fail "$case_name must exit with task-failure status 1"
  jq -e \
    --arg expected_code "$expected_code" \
    --arg expected_category "$expected_category" \
    '
      .status == "failed"
      and .outcome == "not-scored"
      and (.pairs | length == 1)
      and ([.pairs[].status] | all(. == "failed"))
      and ([.pairs[] | .treatment.error.code, .control.error.code]
        | all(. == $expected_code))
      and ([.pairs[] | .treatment.error.category, .control.error.category]
        | all(. == $expected_category))
      and ([.pairs[] | .treatment.request_count, .control.request_count]
        | all(. == 1))
      and ([.pairs[] | .treatment.skill_context, .control.skill_context]
        | sort == ["absent", "present"])
      and ((tostring | contains("provider-only-secret")) | not)
      and ((tostring | contains("body-only-secret")) | not)
    ' "$results_file" >/dev/null \
    || fail "$case_name did not emit its typed, redacted failure result"
  [ "$(wc -l <"$request_log" | tr -d ' ')" -eq 2 ] \
    || fail "$case_name must issue exactly one request per condition"
}

run_missing_credential_case() {
  local artifact_dir="$TEMP_DIR/missing-credential-artifacts"
  local request_log="$TEMP_DIR/missing-credential-requests.ndjson"
  local results_file="$artifact_dir/results.json"
  local exit_code

  : >"$request_log"
  set +e
  OPENROUTER_API_KEY='' \
    CURL_BIN="$FAKE_CURL" \
    MOCK_CURL_MODE='success' \
    REQUEST_LOG="$request_log" \
    "$RUNNER" \
    --profile "$FAIL_PROFILE" \
    --task-file "$TASK_FILE" \
    --skill-file "$SKILL_FILE" \
    --skill-name agents-md \
    --fixture-revision fixture-v1 \
    --artifact-dir "$artifact_dir" \
    >"$TEMP_DIR/missing-credential.stdout" \
    2>"$TEMP_DIR/missing-credential.stderr"
  exit_code=$?
  set -e

  [ "$exit_code" -eq 2 ] || fail "missing credentials must exit with configuration status 2"
  jq -e '
    .result_type == "infrastructure"
    and .status == "failed"
    and .outcome == "not-scored"
    and .error.category == "credentials"
    and .error.code == "credential_missing"
    and ((tostring | contains("test-api-key")) | not)
  ' "$results_file" >/dev/null || fail "missing credentials must be a typed, redacted failure"
  [ ! -s "$request_log" ] || fail "missing credentials must not call the provider"
}

run_missing_credential_case
run_provider_failure_case model-unavailable model-unavailable model_unavailable model
run_provider_failure_case redirect redirect provider_error provider
run_provider_failure_case credentials-rejected credentials-rejected credentials_rejected credentials
run_provider_failure_case rate-limited rate-limited provider_rate_limited provider
run_provider_failure_case provider-error provider-error provider_error provider
run_provider_failure_case timeout timeout request_timeout transport
run_provider_failure_case malformed malformed response_malformed response

echo "api paired runner checks passed"
