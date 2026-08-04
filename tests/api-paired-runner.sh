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
RUBRIC_FILE="$ROOT_DIR/evals/fixtures/api/agents-md/representative-task/rubric.json"

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

model="$(jq -r '.model' "$request_file")"
if jq -e '
  any(.messages[]; .role == "system" and
    (.content | contains("independent rubric judge")))
' "$request_file" >/dev/null; then
  jq -c --arg url "$request_url" --arg kind judge '
    {
      kind: $kind,
      url: $url,
      model,
      messages,
      temperature,
      max_tokens,
      stream,
      provider
    }
  ' "$request_file" >>"$REQUEST_LOG"

  case "${MOCK_JUDGE_MODE:-success}" in
    success)
      if jq -e '[.messages[].content] | any(contains("SKILL_MARKER"))' \
        "$request_file" >/dev/null; then
        judge_score=80
      else
        judge_score=60
      fi
      jq -n --arg model "$model" --argjson score "$judge_score" '{
        id: "mock-judge-response",
        model: $model,
        choices: [{
          index: 0,
          message: {
            role: "assistant",
            content: ({
              score: $score,
              evidence: [
                "The response names supplied project context.",
                "The findings explain a rationale and offer an alternative."
              ]
            } | tojson)
          },
          finish_reason: "stop"
        }],
        usage: {prompt_tokens: 21, completion_tokens: 9, total_tokens: 30}
      }' >"$output_file"
      printf '%s' '200'
      ;;
    malformed)
      jq -n --arg model "$model" '{
        id: "mock-judge-malformed",
        model: $model,
        choices: [{
          index: 0,
          message: {role: "assistant", content: "not-json"},
          finish_reason: "stop"
        }]
      }' >"$output_file"
      printf '%s' '200'
      ;;
    secret)
      jq -n --arg model "$model" '{
        id: "mock-judge-secret",
        model: $model,
        choices: [{
          index: 0,
          message: {
            role: "assistant",
            content: ({score: 70, evidence: ["Bearer secret-token-value"]} | tojson)
          },
          finish_reason: "stop"
        }]
      }' >"$output_file"
      printf '%s' '200'
      ;;
    *)
      echo "unsupported mock judge mode" >&2
      exit 51
      ;;
  esac
  exit 0
fi

jq -c --arg url "$request_url" --arg kind candidate '
  {
    kind: $kind,
    url: $url,
    model,
    messages,
    temperature,
    max_tokens,
    stream,
    provider
  }
' "$request_file" >>"$REQUEST_LOG"

jq -e '
  .provider.allow_fallbacks == false
  and .provider.require_parameters == true
' "$request_file" >/dev/null || { echo "request must preserve provider routing" >&2; exit 48; }

case "$MOCK_CURL_MODE" in
  success)
    if jq -e '[.messages[].content] | any(contains("SKILL-CONTEXT"))' \
      "$request_file" >/dev/null; then
      response_marker="SKILL_MARKER"
    else
      response_marker="BASELINE_MARKER"
    fi
    jq -n --arg model "$model" --arg marker "$response_marker" '{
      id: "mock-response",
      model: $model,
      choices: [{
        index: 0,
        message: {role: "assistant", content: (
          "## Micromanagement Audit\n\n" +
          "## Grounded Findings\n\n" +
          "- Progressive Disclosure: because a hard line is micromanagement; " +
          "alternative: use a project-specific guideline.\n" +
          "- Trust Model Judgment: because a duplicate constraint is prescriptive; " +
          "alternative: rely on model judgment.\n\n" +
          "## Recommendations\n\n" + $marker
        )},
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
  MOCK_JUDGE_MODE='success' \
  REQUEST_LOG="$REQUEST_LOG" \
  "$RUNNER" \
  --profile "$PROFILE_FILE" \
  --task-file "$TASK_FILE" \
  --task-revision agents-md-task-v1 \
  --skill-file "$SKILL_FILE" \
  --skill-revision agents-md-skill-v1 \
  --skill-name agents-md \
  --fixture-revision fixture-v1 \
  --rubric-file "$RUBRIC_FILE" \
  --rubric-revision agents-md-micromanagement-v1 \
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
  and .outcome == "scored"
  and .target_models == ["openai/test-one", "google/test-two"]
  and .judge_model == "anthropic/test-judge"
  and .fixture.revision == "fixture-v1"
  and .fixture.task_revision == "agents-md-task-v1"
  and .fixture.skill_revision == "agents-md-skill-v1"
  and .fixture.rubric_revision == "agents-md-micromanagement-v1"
  and .fixture.skill_name == "agents-md"
  and (.fixture.task_sha256 | startswith("sha256:"))
  and (.fixture.skill_sha256 | startswith("sha256:"))
  and (.fixture.rubric_sha256 | startswith("sha256:"))
  and (.pairs | length == 2)
  and ([.pairs[].status] | all(. == "completed"))
  and ([.pairs[].outcome] | all(. == "scored"))
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
  and ([.pairs[].treatment.deterministic.status,
    .pairs[].control.deterministic.status] | all(. == "passed"))
  and ([.pairs[].treatment.judge.status, .pairs[].control.judge.status]
    | all(. == "scored"))
  and ([.pairs[].treatment.judge.requested_model,
    .pairs[].control.judge.requested_model] | unique == ["anthropic/test-judge"])
  and ([.pairs[].treatment.judge.score] | all(. == 80))
  and ([.pairs[].control.judge.score] | all(. == 60))
  and ([.pairs[].treatment.judge.response.resolved_model,
    .pairs[].control.judge.response.resolved_model]
    | unique == ["anthropic/test-judge"])
  and ([.pairs[].treatment.judge.response.usage.total_tokens,
    .pairs[].control.judge.response.usage.total_tokens] | all(. == 30))
  and ([.pairs[].paired_lift.status] | all(. == "scored"))
  and ([.pairs[].paired_lift.treatment_minus_control] | all(. == 20))
  and ([.pairs[].treatment.timing.duration_seconds,
    .pairs[].control.timing.duration_seconds,
    .pairs[].treatment.judge.timing.duration_seconds,
    .pairs[].control.judge.timing.duration_seconds] | all(type == "number"))
  and ([.pairs[].request.max_turns] | all(. == 1))
  and ([.pairs[].request.stream] | all(. == false))
  and ([.pairs[].provider_routing.gateway] | unique == ["openrouter-chat-completions"])
  and ([.pairs[].provider_routing.allow_fallbacks] | all(. == false))
  and ([.pairs[].treatment.response.content, .pairs[].control.response.content]
    | all(. == null))
  and ((tostring | contains("SKILL_MARKER")) | not)
  and ((tostring | contains("BASELINE_MARKER")) | not)
' "$RESULTS" >/dev/null || fail "paired results do not satisfy the public contract"

jq -s -e '
  length == 8
  and ([.[] | select(.kind == "candidate")] | length == 4)
  and ([.[] | select(.kind == "judge")] | length == 4)
  and ([.[] | select(.kind == "candidate") | .model] | sort == [
    "google/test-two", "google/test-two", "openai/test-one", "openai/test-one"
  ])
  and ([.[] | select(.kind == "judge") | .model] | unique == ["anthropic/test-judge"])
  and ([.[] | select(.kind == "candidate") | .temperature] | unique == [0])
  and ([.[] | select(.kind == "candidate") | .max_tokens] | unique == [2048])
  and ([.[] | select(.kind == "judge") | .max_tokens] | unique == [512])
  and ([.[].stream] | unique == [false])
  and ([.[].provider.allow_fallbacks] | unique == [false])
  and ([.[].provider.require_parameters] | unique == [true])
  and ([.[].url] | unique == ["https://openrouter.ai/api/v1/chat/completions"])
  and ([.[] | select(.kind == "candidate")]
    | .[0].messages[-1].content == .[1].messages[-1].content
      and .[2].messages[-1].content == .[3].messages[-1].content)
  and ([.[] | select(.kind == "candidate") | .messages[]
    | select(.content | contains("SKILL-CONTEXT"))] | length == 2)
  and ([.[] | select(.kind == "judge") | [.messages[].content] | join("\n")
    | select(contains("openai/test-one")
      or contains("google/test-two")
      or contains("treatment")
      or contains("control"))] | length == 0)
  and ([.[] | select(.kind == "judge") | [.messages[].content] | join("\n")
    | select(contains("TASK:") and contains("RUBRIC:")
      and contains("ANONYMIZED CANDIDATE RESPONSE:"))] | length == 4)
  and ([.[] | select(.kind == "judge")
    | [.messages[].content | select(contains("SKILL_MARKER")
      or contains("BASELINE_MARKER"))] | length] | all(. == 1))
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
  MOCK_JUDGE_MODE='success' \
  REQUEST_LOG="$PROFILE_REDACTION_LOG" \
  "$RUNNER" \
  --profile "$PROFILE_WITH_EXTRAS" \
  --task-file "$TASK_FILE" \
  --task-revision agents-md-task-v1 \
  --skill-file "$SKILL_FILE" \
  --skill-revision agents-md-skill-v1 \
  --skill-name agents-md \
  --fixture-revision fixture-v1 \
  --rubric-file "$RUBRIC_FILE" \
  --rubric-revision agents-md-micromanagement-v1 \
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
    --task-revision agents-md-task-v1 \
    --skill-file "$SKILL_FILE" \
    --skill-revision agents-md-skill-v1 \
    --skill-name agents-md \
    --fixture-revision fixture-v1 \
    --rubric-file "$RUBRIC_FILE" \
    --rubric-revision agents-md-micromanagement-v1 \
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

run_judge_failure_case() {
  local case_name="$1"
  local mock_judge_mode="$2"
  local expected_code="$3"
  local expected_category="$4"
  local artifact_dir="$TEMP_DIR/$case_name-judge-artifacts"
  local request_log="$TEMP_DIR/$case_name-judge-requests.ndjson"
  local results_file="$artifact_dir/results.json"
  local exit_code

  : >"$request_log"
  set +e
  OPENROUTER_API_KEY='test-api-key' \
    CURL_BIN="$FAKE_CURL" \
    MOCK_CURL_MODE='success' \
    MOCK_JUDGE_MODE="$mock_judge_mode" \
    REQUEST_LOG="$request_log" \
    "$RUNNER" \
    --profile "$FAIL_PROFILE" \
    --task-file "$TASK_FILE" \
    --task-revision agents-md-task-v1 \
    --skill-file "$SKILL_FILE" \
    --skill-revision agents-md-skill-v1 \
    --skill-name agents-md \
    --fixture-revision fixture-v1 \
    --rubric-file "$RUBRIC_FILE" \
    --rubric-revision agents-md-micromanagement-v1 \
    --artifact-dir "$artifact_dir" \
    >"$TEMP_DIR/$case_name-judge.stdout" \
    2>"$TEMP_DIR/$case_name-judge.stderr"
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
      and ([.pairs[] | .treatment.judge.error.code,
        .control.judge.error.code] | all(. == $expected_code))
      and ([.pairs[] | .treatment.judge.error.category,
        .control.judge.error.category] | all(. == $expected_category))
      and ([.pairs[] | .treatment.judge.status, .control.judge.status]
        | all(. == "failed"))
      and ([.pairs[].paired_lift.status] | all(. == "not-scored"))
      and ((tostring | contains("secret-token-value")) | not)
      and ((tostring | contains("test-api-key")) | not)
    ' "$results_file" >/dev/null \
    || fail "$case_name did not emit its typed, redacted judge failure"
  [ "$(wc -l <"$request_log" | tr -d ' ')" -eq 4 ] \
    || fail "$case_name must issue two candidate and two judge requests"
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
    MOCK_JUDGE_MODE='success' \
    REQUEST_LOG="$request_log" \
    "$RUNNER" \
    --profile "$FAIL_PROFILE" \
    --task-file "$TASK_FILE" \
    --task-revision agents-md-task-v1 \
    --skill-file "$SKILL_FILE" \
    --skill-revision agents-md-skill-v1 \
    --skill-name agents-md \
    --fixture-revision fixture-v1 \
    --rubric-file "$RUBRIC_FILE" \
    --rubric-revision agents-md-micromanagement-v1 \
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
run_judge_failure_case malformed malformed judge_response_malformed response
run_judge_failure_case secret secret judge_redaction_failure security

echo "api paired runner checks passed"
