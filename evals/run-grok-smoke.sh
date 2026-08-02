#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FIXTURE_ROOT="$ROOT_DIR/evals/fixtures/agents-md"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/grok-smoke"
GROK_BIN="${GROK_BIN:-grok}"
FIXTURE_ROOT="$DEFAULT_FIXTURE_ROOT"
ARTIFACT_DIR="$DEFAULT_ARTIFACT_DIR"
MODEL=""
PROVIDER="openrouter"
MAX_TURNS="8"

usage() {
  cat <<'EOF'
Usage: run-grok-smoke.sh [options]

Run the agents-md Grok Build smoke-comparison fixtures (positive + negative).

Options:
  --fixture-root PATH  Fixture directory to execute.
  --artifact-dir PATH  Directory for normalized, redacted results.
  --model MODEL        Requested model id for the selected provider.
  --provider NAME      openrouter (default) or direct-xai (calibration only).
  --max-turns COUNT    Maximum agent turns per fixture.
  --help               Show this help.
EOF
}

fail() {
  echo "grok smoke eval: $*" >&2
  exit 1
}

classify_stderr() {
  local error_file="$1"
  local response_file="$2"

  if [ ! -s "$error_file" ] && [ ! -s "$response_file" ]; then
    printf '%s\n' 'empty'
  elif grep -Eqi 'unauthori[sz]ed|authentication|not signed in|api[ _-]?key|credential|\b401\b' \
    "$error_file" "$response_file" 2>/dev/null; then
    printf '%s\n' 'authentication_rejected'
  elif grep -Eqi 'forbidden|permission denied|\b403\b' \
    "$error_file" "$response_file" 2>/dev/null; then
    printf '%s\n' 'authorization_rejected'
  elif grep -Eqi 'model.*(not found|unavailable)|no endpoints|\b404\b' \
    "$error_file" "$response_file" 2>/dev/null; then
    printf '%s\n' 'model_unavailable'
  elif grep -Eqi 'rate limit|too many requests|\b429\b' \
    "$error_file" "$response_file" 2>/dev/null; then
    printf '%s\n' 'rate_limited'
  elif grep -Eqi 'unsupported|invalid.*(config|provider|model)|unknown (field|variant|config)' \
    "$error_file" "$response_file" 2>/dev/null; then
    printf '%s\n' 'configuration_invalid'
  else
    printf '%s\n' 'unclassified'
  fi
}

write_isolated_config() {
  local grok_home="$1"
  local requested_model="$2"
  local provider_name="$3"
  local config_path="$grok_home/config.toml"

  mkdir -p "$grok_home"
  if [ "$provider_name" = "openrouter" ]; then
    cat >"$config_path" <<EOF
[cli]
auto_update = false

[compat.claude]
skills = false
instructions = false

[compat.cursor]
skills = false

[model.eval-model]
model = "${requested_model}"
base_url = "https://openrouter.ai/api/v1"
name = "Grok via OpenRouter"
env_key = "OPENROUTER_API_KEY"
api_backend = "chat_completions"
context_window = 131072

[models]
default = "eval-model"
EOF
  else
    cat >"$config_path" <<EOF
[cli]
auto_update = false

[compat.claude]
skills = false
instructions = false

[compat.cursor]
skills = false

[model.eval-model]
model = "${requested_model}"
base_url = "https://api.x.ai/v1"
name = "Grok via direct xAI"
env_key = "XAI_API_KEY"
api_backend = "chat_completions"
context_window = 131072

[models]
default = "eval-model"
EOF
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture-root)
      FIXTURE_ROOT="${2:-}"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --max-turns)
      MAX_TURNS="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

command -v "$GROK_BIN" >/dev/null 2>&1 || fail "Grok executable not found: $GROK_BIN"
command -v git >/dev/null 2>&1 || fail "git executable not found"
command -v jq >/dev/null 2>&1 || fail "jq executable not found"

case "$PROVIDER" in
  openrouter)
    RESULT_PROVIDER="openrouter"
    RESULT_GATEWAY="openrouter-chat-completions"
    CREDENTIAL_ENV="OPENROUTER_API_KEY"
    [ -n "$MODEL" ] || MODEL="x-ai/grok-4.5"
    ;;
  direct-xai)
    RESULT_PROVIDER="xai"
    RESULT_GATEWAY="xai-direct"
    CREDENTIAL_ENV="XAI_API_KEY"
    [ -n "$MODEL" ] || MODEL="grok-4.5"
    ;;
  *)
    fail "unsupported provider: $PROVIDER (expected openrouter or direct-xai)"
    ;;
esac

[[ "$MAX_TURNS" =~ ^[1-9][0-9]*$ ]] || fail "max-turns must be a positive integer"
[ -d "$FIXTURE_ROOT" ] || fail "fixture root does not exist: $FIXTURE_ROOT"
[ -d "$ROOT_DIR/skills/agents-md" ] || fail "agents-md skill is missing"

REQUIRED_CASES=(
  "expected-trigger"
  "expected-non-trigger"
)
for required_case in "${REQUIRED_CASES[@]}"; do
  [ -d "$FIXTURE_ROOT/$required_case" ] || fail "required fixture is missing: $required_case"
done

CREDENTIAL_STATE="missing"
if [ -n "${!CREDENTIAL_ENV:-}" ]; then
  CREDENTIAL_STATE="present"
fi
if [ "$CREDENTIAL_STATE" != "present" ]; then
  fail "$CREDENTIAL_ENV must be set for provider $PROVIDER"
fi

mkdir -p "$ARTIFACT_DIR"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
RESULTS_NDJSON="$TEMP_DIR/results.ndjson"
ISOLATED_HOME="$TEMP_DIR/home"
ISOLATED_GROK_HOME="$TEMP_DIR/grok-home"
mkdir -p "$ISOLATED_HOME"
write_isolated_config "$ISOLATED_GROK_HOME" "$MODEL" "$PROVIDER"

HARNESS_VERSION="$("$GROK_BIN" --version 2>/dev/null || printf 'unknown')"

DISCOVERY_WORKSPACE="$TEMP_DIR/discovery-workspace"
mkdir -p "$DISCOVERY_WORKSPACE"
cp -R "$FIXTURE_ROOT/expected-trigger/project/." "$DISCOVERY_WORKSPACE"
git -C "$DISCOVERY_WORKSPACE" init --quiet
mkdir -p "$DISCOVERY_WORKSPACE/.agents/skills"
cp -R "$ROOT_DIR/skills/agents-md" "$DISCOVERY_WORKSPACE/.agents/skills/agents-md"
DISCOVERY_JSON="$TEMP_DIR/discovery.json"
DISCOVERY_ERR="$TEMP_DIR/discovery.err"
set +e
(
  cd "$DISCOVERY_WORKSPACE"
  HOME="$ISOLATED_HOME" \
    GROK_HOME="$ISOLATED_GROK_HOME" \
    GROK_DISABLE_AUTOUPDATER=1 \
    GROK_CLAUDE_SKILLS_ENABLED=false \
    GROK_CURSOR_SKILLS_ENABLED=false \
    "$GROK_BIN" inspect --json
) >"$DISCOVERY_JSON" 2>"$DISCOVERY_ERR"
DISCOVERY_EXIT=$?
set -e

if [ "$DISCOVERY_EXIT" -ne 0 ] || ! jq -e . "$DISCOVERY_JSON" >/dev/null 2>&1; then
  fail "grok inspect --json failed to produce discovery evidence"
fi

PROJECT_INSTRUCTIONS_FOUND="$(jq -r '
  ([.projectInstructions // [] | .[] | select(.scope == "project")] | length) > 0
' "$DISCOVERY_JSON")"
AGENTS_MD_SKILL_FOUND="$(jq -r '
  ([.skills // [] | .[] | select(.name == "agents-md")] | length) > 0
' "$DISCOVERY_JSON")"
SKILL_SOURCE="$(jq -r '
  [.skills // [] | .[] | select(.name == "agents-md") | .source.type] | first // "missing"
' "$DISCOVERY_JSON")"

if [ "$PROJECT_INSTRUCTIONS_FOUND" != "true" ] || [ "$AGENTS_MD_SKILL_FOUND" != "true" ] \
  || [ "$SKILL_SOURCE" != "project" ]; then
  fail "discovery must report project AGENTS.md instructions and a project-scoped agents-md skill"
fi

for case_name in "${REQUIRED_CASES[@]}"; do
  fixture_dir="$FIXTURE_ROOT/$case_name"
  EXPECTATION_FILE="$fixture_dir/expectation.json"
  PROMPT_FILE="$fixture_dir/prompt.txt"
  PROJECT_DIR="$fixture_dir/project"

  [ -f "$EXPECTATION_FILE" ] || fail "missing expectation for $case_name"
  [ -f "$PROMPT_FILE" ] || fail "missing prompt for $case_name"
  [ -d "$PROJECT_DIR" ] || fail "missing project fixture for $case_name"
  PROMPT="$(<"$PROMPT_FILE")"

  WORKSPACE="$TEMP_DIR/$case_name"
  cp -R "$PROJECT_DIR/." "$WORKSPACE"
  git -C "$WORKSPACE" init --quiet
  ORIGINAL_PROJECT="$TEMP_DIR/$case_name-original"
  cp -R "$PROJECT_DIR" "$ORIGINAL_PROJECT"
  mkdir -p "$WORKSPACE/.agents/skills"
  cp -R "$ROOT_DIR/skills/agents-md" "$WORKSPACE/.agents/skills/agents-md"
  if [ "$case_name" = "expected-trigger" ]; then
    mkdir -p "$WORKSPACE/evaluation"
    : >"$WORKSPACE/evaluation/quality-report.md"
  fi

  CASE_GROK_HOME="$TEMP_DIR/$case_name-grok-home"
  write_isolated_config "$CASE_GROK_HOME" "$MODEL" "$PROVIDER"
  RESPONSE_FILE="$TEMP_DIR/$case_name-response.json"
  ERROR_FILE="$TEMP_DIR/$case_name-error.txt"
  START_EPOCH="$(date +%s)"
  set +e
  (
    cd "$WORKSPACE"
    HOME="$ISOLATED_HOME" \
      GROK_HOME="$CASE_GROK_HOME" \
      GROK_DISABLE_AUTOUPDATER=1 \
      GROK_CLAUDE_SKILLS_ENABLED=false \
      GROK_CURSOR_SKILLS_ENABLED=false \
      EVAL_CASE_NAME="$case_name" \
      EVAL_PROVIDER="$PROVIDER" \
      "$GROK_BIN" \
        -p "$PROMPT" \
        -m eval-model \
        --output-format json \
        --always-approve \
        --max-turns "$MAX_TURNS" \
        --no-memory \
        --disable-web-search
  ) >"$RESPONSE_FILE" 2>"$ERROR_FILE"
  EXIT_CODE=$?
  set -e
  ELAPSED_SECONDS="$(( $(date +%s) - START_EPOCH ))"

  RESPONSE_STATE="empty"
  if [ -s "$RESPONSE_FILE" ]; then
    if jq -e . "$RESPONSE_FILE" >/dev/null 2>&1; then
      RESPONSE_STATE="valid_json"
    else
      RESPONSE_STATE="invalid_json"
    fi
  fi

  RESOLVED_MODEL=""
  COST_USD=""
  if [ "$RESPONSE_STATE" = "valid_json" ]; then
    RESOLVED_MODEL="$(jq -r '
      (.modelUsage // {} | keys[0] // empty) // (.model // empty)
    ' "$RESPONSE_FILE" 2>/dev/null || true)"
    COST_USD="$(jq -r '
      if (.total_cost_usd | type) == "number" then .total_cost_usd
      else empty end
    ' "$RESPONSE_FILE" 2>/dev/null || true)"
  fi

  EXPECTED_OUTCOME="$(jq -r '.outcome' "$EXPECTATION_FILE")"
  EVIDENCE_PATH="$(jq -r '.evidence_file' "$EXPECTATION_FILE")"
  REQUIRED_PATTERN="$(jq -r '.required_pattern // empty' "$EXPECTATION_FILE")"
  EVIDENCE_ABSENT="$(jq -r '.evidence_absent // false' "$EXPECTATION_FILE")"
  EVIDENCE_FILE="$WORKSPACE/$EVIDENCE_PATH"
  EVIDENCE_STATUS="missing"
  if [ "$EVIDENCE_ABSENT" = "true" ] && [ ! -e "$EVIDENCE_FILE" ]; then
    EVIDENCE_STATUS="absent"
  elif [ -f "$EVIDENCE_FILE" ] && { [ -z "$REQUIRED_PATTERN" ] || grep -qF -- "$REQUIRED_PATTERN" "$EVIDENCE_FILE"; }; then
    EVIDENCE_STATUS="matched"
  fi

  ACTUAL_OUTCOME="fail"
  if [ "$EVIDENCE_STATUS" = "matched" ] || [ "$EVIDENCE_STATUS" = "absent" ]; then
    ACTUAL_OUTCOME="$EXPECTED_OUTCOME"
  fi
  SUMMARY="Observable fixture evidence: $EVIDENCE_STATUS"
  rm -f "$EVIDENCE_FILE"
  rmdir "$WORKSPACE/evaluation" 2>/dev/null || true
  WORKSPACE_CLEAN="true"
  if ! diff -qr --exclude='.agents' --exclude='.git' --exclude='.grok' \
    "$ORIGINAL_PROJECT" "$WORKSPACE" >/dev/null; then
    WORKSPACE_CLEAN="false"
  fi

  ERROR_CATEGORY=""
  ERROR_SUMMARY=""
  STDERR_STATE="empty"
  STDERR_CATEGORY="empty"
  STDERR_FINGERPRINT=""
  if [ -s "$ERROR_FILE" ]; then
    STDERR_STATE="nonempty"
    STDERR_CATEGORY="$(classify_stderr "$ERROR_FILE" "$RESPONSE_FILE")"
    STDERR_FINGERPRINT="sha256:$(shasum -a 256 "$ERROR_FILE" | awk '{print $1}')"
  elif [ "$RESPONSE_STATE" = "valid_json" ] \
    && jq -e '.type == "error"' "$RESPONSE_FILE" >/dev/null 2>&1; then
    STDERR_STATE="nonempty"
    STDERR_CATEGORY="$(classify_stderr "$ERROR_FILE" "$RESPONSE_FILE")"
  fi

  if [ "$RESPONSE_STATE" = "invalid_json" ]; then
    ERROR_CATEGORY="adapter_output_invalid"
    ERROR_SUMMARY="Grok emitted malformed JSON"
  elif [ "$EXIT_CODE" -ne 0 ]; then
    ERROR_CATEGORY="harness_failed"
    ERROR_SUMMARY="Grok exited with status $EXIT_CODE"
  elif [ "$RESPONSE_STATE" = "valid_json" ] \
    && jq -e '.type == "error"' "$RESPONSE_FILE" >/dev/null 2>&1; then
    ERROR_CATEGORY="harness_failed"
    ERROR_SUMMARY="Grok returned an error object"
  fi

  STATUS="pass"
  if [ "$EXIT_CODE" -ne 0 ] \
    || [ "$RESPONSE_STATE" != "valid_json" ] \
    || [ "$ACTUAL_OUTCOME" != "$EXPECTED_OUTCOME" ] \
    || [ "$WORKSPACE_CLEAN" != "true" ] \
    || { [ "$RESPONSE_STATE" = "valid_json" ] && jq -e '.type == "error"' "$RESPONSE_FILE" >/dev/null 2>&1; }; then
    STATUS="fail"
  fi

  jq -n \
    --arg case_name "$case_name" \
    --arg status "$STATUS" \
    --arg expected_outcome "$EXPECTED_OUTCOME" \
    --arg actual_outcome "$ACTUAL_OUTCOME" \
    --arg summary "$SUMMARY" \
    --arg error_summary "$ERROR_SUMMARY" \
    --arg error_category "$ERROR_CATEGORY" \
    --arg response_state "$RESPONSE_STATE" \
    --arg stderr_state "$STDERR_STATE" \
    --arg stderr_category "$STDERR_CATEGORY" \
    --arg stderr_fingerprint "$STDERR_FINGERPRINT" \
    --arg evidence_path "$EVIDENCE_PATH" \
    --arg evidence_status "$EVIDENCE_STATUS" \
    --arg workspace_clean "$WORKSPACE_CLEAN" \
    --arg resolved_model "$RESOLVED_MODEL" \
    --arg cost_usd "$COST_USD" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson elapsed_seconds "$ELAPSED_SECONDS" \
    '{
      case: $case_name,
      status: $status,
      expected: {outcome: $expected_outcome},
      actual: {outcome: $actual_outcome},
      summary: $summary,
      evidence: {path: ($case_name + "/" + $evidence_path), status: $evidence_status},
      workspace_clean: ($workspace_clean == "true"),
      exit_code: $exit_code,
      elapsed_seconds: $elapsed_seconds,
      resolved_model: (if $resolved_model == "" then null else $resolved_model end),
      model_resolution_status: (if $resolved_model == "" then "not-reported" else "reported" end),
      cost_usd: (if $cost_usd == "" then null else ($cost_usd | tonumber) end),
      cost_status: (if $cost_usd == "" then "not-reported" else "reported" end),
      error: $error_summary
    } + (
      if $error_category == "" then {}
      else {
        error_category: $error_category,
        error_diagnostics: ({
          response_state: $response_state,
          stderr_state: $stderr_state,
          stderr_category: $stderr_category
        } + (
          if $stderr_fingerprint == "" then {}
          else {stderr_fingerprint: $stderr_fingerprint}
          end
        ))
      }
      end
    )' >>"$RESULTS_NDJSON"
  if [ "$ERROR_CATEGORY" != "" ]; then
    echo "Grok diagnostic for $case_name: stderr=$STDERR_CATEGORY${STDERR_FINGERPRINT:+ ($STDERR_FINGERPRINT)}" >&2
  fi
done

jq -s \
  --arg model "$MODEL" \
  --arg harness_version "$HARNESS_VERSION" \
  --arg credential_state "$CREDENTIAL_STATE" \
  --arg provider "$RESULT_PROVIDER" \
  --arg gateway "$RESULT_GATEWAY" \
  --arg skill_source "$SKILL_SOURCE" \
  --argjson project_instructions_found "$PROJECT_INSTRUCTIONS_FOUND" \
  --argjson agents_md_skill_found "$AGENTS_MD_SKILL_FOUND" \
  '{
    suite: "smoke",
    adapter: "grok-build-native",
    harness: "grok-build",
    harness_version: $harness_version,
    provider: $provider,
    gateway: $gateway,
    credential_state: $credential_state,
    requested_model: $model,
    auto_update_disabled: true,
    discovery: {
      project_instructions_found: $project_instructions_found,
      agents_md_skill_found: $agents_md_skill_found,
      skill_source: $skill_source
    },
    cases: .
  }' "$RESULTS_NDJSON" >"$ARTIFACT_DIR/results.json"

if jq -e '[.cases[].status] | all(. == "pass")' "$ARTIFACT_DIR/results.json" >/dev/null; then
  echo "Grok smoke evaluation passed: $ARTIFACT_DIR/results.json"
  exit 0
fi

echo "Grok smoke evaluation failed: $ARTIFACT_DIR/results.json" >&2
exit 1
