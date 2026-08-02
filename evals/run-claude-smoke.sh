#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FIXTURE_ROOT="$ROOT_DIR/evals/fixtures/agents-md"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/claude-smoke"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
FIXTURE_ROOT="$DEFAULT_FIXTURE_ROOT"
ARTIFACT_DIR="$DEFAULT_ARTIFACT_DIR"
MODEL="anthropic/claude-haiku-4.5"
MAX_TURNS="8"
MAX_BUDGET_USD="2"

usage() {
  cat <<'EOF'
Usage: run-claude-smoke.sh [options]

Run the agents-md Claude Code smoke-evaluation fixtures.

Options:
  --fixture-root PATH  Fixture directory to execute.
  --artifact-dir PATH  Directory for normalized, redacted results.
  --model MODEL        Requested Claude model.
  --max-turns COUNT    Maximum Claude agent turns per fixture.
  --max-budget-usd USD Maximum Claude spend per fixture.
  --help               Show this help.
EOF
}

fail() {
  echo "claude smoke eval: $*" >&2
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
    --max-turns)
      MAX_TURNS="${2:-}"
      shift 2
      ;;
    --max-budget-usd)
      MAX_BUDGET_USD="${2:-}"
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

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || fail "Claude executable not found: $CLAUDE_BIN"
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
HARNESS_VERSION="$("$CLAUDE_BIN" --version 2>/dev/null || printf 'unknown')"

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
  PLUGIN_DIR="$WORKSPACE/.claude/eval-plugin"
  mkdir -p "$PLUGIN_DIR/skills"
  cp -R "$ROOT_DIR/skills/agents-md" "$PLUGIN_DIR/skills/agents-md"
  mkdir -p "$PLUGIN_DIR/.claude-plugin"
  cat >"$PLUGIN_DIR/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "agents-md-eval",
  "version": "0.0.0",
  "description": "Temporary instrumentation for agents-md evaluation"
}
EOF
  RESPONSE_FILE="$TEMP_DIR/$case_name-response.json"
  ERROR_FILE="$TEMP_DIR/$case_name-error.txt"
  START_EPOCH="$(date +%s)"
  set +e
  (
    cd "$WORKSPACE"
    EVAL_CASE_NAME="$case_name" "$CLAUDE_BIN" \
      -p "$(<"$PROMPT_FILE")" \
      --model "$MODEL" \
      --plugin-dir "$PLUGIN_DIR" \
      --output-format json \
      --max-turns "$MAX_TURNS" \
      --max-budget-usd "$MAX_BUDGET_USD" \
      --permission-mode acceptEdits \
      --no-session-persistence
  ) >"$RESPONSE_FILE" 2>"$ERROR_FILE"
  EXIT_CODE=$?
  set -e
  ELAPSED_SECONDS="$(( $(date +%s) - START_EPOCH ))"

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
  if ! diff -qr --exclude='.claude' "$ORIGINAL_PROJECT" "$WORKSPACE" >/dev/null; then
    WORKSPACE_CLEAN="false"
  fi
  COST="$(jq -r '.total_cost_usd // 0' "$RESPONSE_FILE" 2>/dev/null || printf '0')"
  RESOLVED_MODEL="$(jq -r '
    .modelUsage // {} | keys[0] // empty
  ' "$RESPONSE_FILE" 2>/dev/null || true)"
  ERROR_SUMMARY=""
  if [ "$EXIT_CODE" -ne 0 ]; then
    ERROR_SUMMARY="Claude exited with status $EXIT_CODE"
  fi

  STATUS="pass"
  if [ "$EXIT_CODE" -ne 0 ] || [ "$ACTUAL_OUTCOME" != "$EXPECTED_OUTCOME" ] || [ "$WORKSPACE_CLEAN" != "true" ] || [ -z "$RESOLVED_MODEL" ]; then
    STATUS="fail"
  fi

  jq -n \
    --arg case_name "$case_name" \
    --arg status "$STATUS" \
    --arg expected_outcome "$EXPECTED_OUTCOME" \
    --arg actual_outcome "$ACTUAL_OUTCOME" \
    --arg summary "$SUMMARY" \
    --arg error_summary "$ERROR_SUMMARY" \
    --arg evidence_path "$EVIDENCE_PATH" \
    --arg evidence_status "$EVIDENCE_STATUS" \
    --arg workspace_clean "$WORKSPACE_CLEAN" \
    --arg resolved_model "$RESOLVED_MODEL" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson elapsed_seconds "$ELAPSED_SECONDS" \
    --argjson cost "$COST" \
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
      resolved_model: $resolved_model,
      cost_usd: $cost,
      error: $error_summary
    }' >>"$RESULTS_NDJSON"
done

jq -s \
  --arg model "$MODEL" \
  --arg harness_version "$HARNESS_VERSION" \
  '{
    suite: "smoke",
    harness: "claude-code",
    harness_version: $harness_version,
    requested_model: $model,
    cases: .,
    aggregate_cost_usd: ([.[].cost_usd] | add)
  }' "$RESULTS_NDJSON" >"$ARTIFACT_DIR/results.json"

if jq -e '[.cases[].status] | all(. == "pass")' "$ARTIFACT_DIR/results.json" >/dev/null; then
  echo "Claude smoke evaluation passed: $ARTIFACT_DIR/results.json"
  exit 0
fi

echo "Claude smoke evaluation failed: $ARTIFACT_DIR/results.json" >&2
exit 1
