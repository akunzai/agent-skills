#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FIXTURE_ROOT="$ROOT_DIR/evals/fixtures/agents-md"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/codex-smoke"
CODEX_BIN="${CODEX_BIN:-codex}"
FIXTURE_ROOT="$DEFAULT_FIXTURE_ROOT"
ARTIFACT_DIR="$DEFAULT_ARTIFACT_DIR"
MODEL="gpt-5.6-luna"
EFFORT="medium"

usage() {
  cat <<'EOF'
Usage: run-codex-smoke.sh [options]

Run the agents-md Codex CLI smoke-evaluation fixtures.

Options:
  --fixture-root PATH  Fixture directory to execute.
  --artifact-dir PATH  Directory for normalized, redacted results.
  --model MODEL        Requested Codex model.
  --effort LEVEL       Codex reasoning effort: low, medium, high, or xhigh.
  --help               Show this help.
EOF
}

fail() {
  echo "codex smoke eval: $*" >&2
  exit 1
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
    --effort)
      EFFORT="${2:-}"
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

command -v "$CODEX_BIN" >/dev/null 2>&1 || fail "Codex executable not found: $CODEX_BIN"
[ -n "$MODEL" ] || fail "model must not be empty"
case "$EFFORT" in
  low|medium|high|xhigh) ;;
  *) fail "unsupported effort: $EFFORT (expected low, medium, high, or xhigh)" ;;
esac
[ -d "$FIXTURE_ROOT" ] || fail "fixture root does not exist: $FIXTURE_ROOT"
[ -d "$ROOT_DIR/skills/agents-md" ] || fail "agents-md skill is missing"

REQUIRED_CASES=(
  "expected-trigger"
  "expected-non-trigger"
  "missing-prerequisite"
)
FIXTURE_COUNT="$(find "$FIXTURE_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[ "$FIXTURE_COUNT" -eq "${#REQUIRED_CASES[@]}" ] || fail "fixture root must contain exactly ${#REQUIRED_CASES[@]} cases"
for required_case in "${REQUIRED_CASES[@]}"; do
  [ -d "$FIXTURE_ROOT/$required_case" ] || fail "required fixture is missing: $required_case"
done

mkdir -p "$ARTIFACT_DIR"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
RESULTS_NDJSON="$TEMP_DIR/results.ndjson"
HARNESS_VERSION="$("$CODEX_BIN" --version 2>/dev/null || printf 'unknown')"

for case_name in "${REQUIRED_CASES[@]}"; do
  fixture_dir="$FIXTURE_ROOT/$case_name"
  EXPECTATION_FILE="$fixture_dir/expectation.json"
  PROMPT_FILE="$fixture_dir/prompt.txt"
  PROJECT_DIR="$fixture_dir/project"

  [ -f "$EXPECTATION_FILE" ] || fail "missing expectation for $case_name"
  [ -f "$PROMPT_FILE" ] || fail "missing prompt for $case_name"
  [ -d "$PROJECT_DIR" ] || fail "missing project fixture for $case_name"

  WORKSPACE="$TEMP_DIR/$case_name"
  cp -R "$PROJECT_DIR/." "$WORKSPACE"
  ORIGINAL_PROJECT="$TEMP_DIR/$case_name-original"
  cp -R "$PROJECT_DIR" "$ORIGINAL_PROJECT"
  SKILL_DIR="$WORKSPACE/.agents/skills/agents-md"
  mkdir -p "$(dirname "$SKILL_DIR")"
  cp -R "$ROOT_DIR/skills/agents-md" "$SKILL_DIR"
  RESPONSE_FILE="$TEMP_DIR/$case_name-response.jsonl"
  ERROR_FILE="$TEMP_DIR/$case_name-error.txt"
  START_EPOCH="$(date +%s)"
  set +e
  (
    cd "$WORKSPACE"
    EVAL_CASE_NAME="$case_name" "$CODEX_BIN" exec \
      --json \
      --ephemeral \
      --ignore-user-config \
      --sandbox workspace-write \
      --model "$MODEL" \
      --config "model_reasoning_effort=\"$EFFORT\"" \
      "$(<"$PROMPT_FILE")"
  ) >"$RESPONSE_FILE" 2>"$ERROR_FILE"
  EXIT_CODE=$?
  set -e
  ELAPSED_SECONDS="$(( $(date +%s) - START_EPOCH ))"

  RESPONSE_STATE="empty"
  if [ -s "$RESPONSE_FILE" ]; then
    jq -s 'all(type == "object")' "$RESPONSE_FILE" >/dev/null 2>&1 || RESPONSE_STATE="invalid_jsonl"
    [ "$RESPONSE_STATE" = "invalid_jsonl" ] || RESPONSE_STATE="valid_jsonl"
  fi
  TURN_COMPLETED=false
  USAGE='{"input_tokens":null,"cached_input_tokens":null,"output_tokens":null,"reasoning_output_tokens":null}'
  if [ "$RESPONSE_STATE" = "valid_jsonl" ]; then
    TURN_COMPLETED="$(jq -s '[.[] | select(.type == "turn.completed")] | length > 0' "$RESPONSE_FILE")"
    USAGE="$(jq -s '[.[] | select(.type == "turn.completed") | .usage // empty] | last // {input_tokens: null, cached_input_tokens: null, output_tokens: null, reasoning_output_tokens: null}' "$RESPONSE_FILE")"
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
  if ! diff -qr --exclude='.agents' "$ORIGINAL_PROJECT" "$WORKSPACE" >/dev/null; then
    WORKSPACE_CLEAN="false"
  fi

  ERROR_CATEGORY=""
  ERROR_SUMMARY=""
  if [ "$RESPONSE_STATE" = "invalid_jsonl" ]; then
    ERROR_CATEGORY="adapter_output_invalid"
    ERROR_SUMMARY="Codex emitted malformed JSONL"
  elif [ "$EXIT_CODE" -ne 0 ]; then
    ERROR_CATEGORY="harness_failed"
    ERROR_SUMMARY="Codex exited with status $EXIT_CODE"
  elif [ "$TURN_COMPLETED" != "true" ]; then
    ERROR_CATEGORY="adapter_output_incomplete"
    ERROR_SUMMARY="Codex did not emit a completed turn"
  fi

  STATUS="pass"
  if [ "$EXIT_CODE" -ne 0 ] || [ "$RESPONSE_STATE" != "valid_jsonl" ] || [ "$TURN_COMPLETED" != "true" ] || [ "$ACTUAL_OUTCOME" != "$EXPECTED_OUTCOME" ] || [ "$WORKSPACE_CLEAN" != "true" ]; then
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
    --arg evidence_path "$EVIDENCE_PATH" \
    --arg evidence_status "$EVIDENCE_STATUS" \
    --arg workspace_clean "$WORKSPACE_CLEAN" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson elapsed_seconds "$ELAPSED_SECONDS" \
    --argjson usage "$USAGE" \
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
      resolved_model: null,
      model_resolution_status: "not-reported",
      cost_usd: null,
      cost_status: "not-reported",
      usage: $usage,
      error: $error_summary
    } + (if $error_category == "" then {} else {error_category: $error_category, error_diagnostics: {response_state: $response_state}} end)' >>"$RESULTS_NDJSON"
done

jq -s \
  --arg model "$MODEL" \
  --arg effort "$EFFORT" \
  --arg harness_version "$HARNESS_VERSION" \
  '{
    suite: "smoke",
    adapter: "codex-cli-native",
    harness: "codex-cli",
    harness_version: $harness_version,
    provider: "openai",
    gateway: "codex-cli",
    requested_model: $model,
    requested_effort: $effort,
    resolved_model: null,
    model_resolution_status: "not-reported",
    aggregate_cost_usd: null,
    aggregate_cost_status: "not-reported",
    cases: .
  }' "$RESULTS_NDJSON" >"$ARTIFACT_DIR/results.json"

if jq -e '[.cases[].status] | all(. == "pass")' "$ARTIFACT_DIR/results.json" >/dev/null; then
  echo "Codex smoke evaluation passed: $ARTIFACT_DIR/results.json"
  exit 0
fi

echo "Codex smoke evaluation failed: $ARTIFACT_DIR/results.json" >&2
exit 1
