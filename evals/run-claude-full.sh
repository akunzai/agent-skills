#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FIXTURE_ROOT="$ROOT_DIR/evals/fixtures/full"
DEFAULT_BASELINE="$ROOT_DIR/evals/baselines/claude-full-v1.json"
DEFAULT_ARTIFACT_DIR="${TMPDIR:-/tmp}/agent-skills-evals/claude-full"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
FIXTURE_ROOT="$DEFAULT_FIXTURE_ROOT"
BASELINE="$DEFAULT_BASELINE"
ARTIFACT_DIR="$DEFAULT_ARTIFACT_DIR"
MODEL="anthropic/claude-sonnet-5"
MAX_TURNS="8"
MAX_BUDGET_USD="2"
EFFORT="medium"
REPLICAS="3"

usage() {
  cat <<'EOF'
Usage: run-claude-full.sh [options]

Run the three-replica Claude Code release-baseline evaluation suite.

Options:
  --fixture-root PATH  Versioned full-suite fixture directory.
  --baseline PATH      Approved redacted baseline summary.
  --artifact-dir PATH  Directory for normalized, redacted results.
  --model MODEL        Requested Claude model.
  --max-turns COUNT    Maximum Claude agent turns per fixture.
  --max-budget-usd USD Maximum Claude spend per fixture.
  --effort LEVEL       Claude reasoning effort: low, medium, high, xhigh, or max.
  --help               Show this help.
EOF
}

fail() { echo "claude full eval: $*" >&2; exit 1; }

classify_provider_error() {
  local error_file="$1"

  if grep -qiE 'rate limit|too many requests|status[[:space:]]*429|(^|[^[:digit:]])429([^[:digit:]]|$)' "$error_file"; then
    printf '%s' rate_limited
  elif grep -qiE 'budget|quota|insufficient (credits|funds)|credit balance|spend limit' "$error_file"; then
    printf '%s' budget_exhausted
  elif grep -qiE 'authentication|unauthorized|invalid api key|api key.*invalid|(^|[^[:digit:]])(401|403)([^[:digit:]]|$)' "$error_file"; then
    printf '%s' authentication_failed
  else
    printf '%s' unknown
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture-root) FIXTURE_ROOT="${2:-}"; shift 2 ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --max-turns) MAX_TURNS="${2:-}"; shift 2 ;;
    --max-budget-usd) MAX_BUDGET_USD="${2:-}"; shift 2 ;;
    --effort) EFFORT="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || fail "Claude executable not found: $CLAUDE_BIN"
[ -d "$FIXTURE_ROOT" ] || fail "fixture root does not exist: $FIXTURE_ROOT"
[ -f "$BASELINE" ] || fail "baseline does not exist: $BASELINE"
[[ "$MAX_TURNS" =~ ^[1-9][0-9]*$ ]] || fail "max turns must be a positive integer"
case "$EFFORT" in
  low|medium|high|xhigh|max) ;;
  *) fail "effort must be low, medium, high, xhigh, or max" ;;
esac
[[ "$REPLICAS" -eq 3 ]] || fail "full suite requires exactly three replicas"
[ "$MODEL" = "anthropic/claude-sonnet-5" ] || fail "full suite baseline requires anthropic/claude-sonnet-5"

FIXTURES=()
while IFS= read -r fixture_dir; do
  FIXTURES+=("$fixture_dir")
done < <(find "$FIXTURE_ROOT" -mindepth 2 -maxdepth 2 -type d | sort)
[ "${#FIXTURES[@]}" -eq 15 ] || fail "full suite must contain exactly 15 cases"
for fixture_dir in "${FIXTURES[@]}"; do
  for required in expectation.json prompt.txt project; do
    [ -e "$fixture_dir/$required" ] || fail "missing $required in $fixture_dir"
  done
  skill="$(jq -r '.skill // empty' "$fixture_dir/expectation.json")"
  [ -d "$ROOT_DIR/skills/$skill" ] || fail "unknown fixture skill in $fixture_dir"
done

EXPECTED_CASES="$(printf '%s\n' "${FIXTURES[@]#"$FIXTURE_ROOT"/}" | jq -R . | jq -s .)"
jq -e --argjson cases "$EXPECTED_CASES" '
  .version == 1 and .suite == "full" and .harness == "claude-code"
  and (.cases | map(.case) | sort) == ($cases | sort)
  and .hard_check.minimum_passing_replicas == 2
  and .hard_check.all_cases_accepted == true
  and .profile.effort == "medium"
  and .profile.dynamic_system_prompt_sections_excluded == true
' "$BASELINE" >/dev/null || fail "baseline does not match versioned fixtures"

mkdir -p "$ARTIFACT_DIR"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
RESULTS_NDJSON="$TEMP_DIR/results.ndjson"
REPLICA_CHECKPOINT="$ARTIFACT_DIR/replicas.ndjson"
: > "$REPLICA_CHECKPOINT"
HARNESS_VERSION="$("$CLAUDE_BIN" --version 2>/dev/null || printf 'unknown')"
ABORT_REASON=""

for fixture_dir in "${FIXTURES[@]}"; do
  case_id="${fixture_dir#"$FIXTURE_ROOT"/}"
  EXPECTATION_FILE="$fixture_dir/expectation.json"
  PROMPT_FILE="$fixture_dir/prompt.txt"
  PROJECT_DIR="$fixture_dir/project"
  SKILL="$(jq -r '.skill' "$EXPECTATION_FILE")"
  EXPECTED_OUTCOME="$(jq -r '.outcome' "$EXPECTATION_FILE")"
  EVIDENCE_PATH="$(jq -r '.evidence_file' "$EXPECTATION_FILE")"
  REQUIRED_PATTERN="$(jq -r '.required_pattern // empty' "$EXPECTATION_FILE")"
  EVIDENCE_ABSENT="$(jq -r '.evidence_absent // false' "$EXPECTATION_FILE")"
  FIXTURE_HASH="$(cd "$fixture_dir" && find . -type f -print | sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256 | awk '{print $1}')"
  case_results="$TEMP_DIR/${case_id//\//-}.ndjson"

  for replica in 1 2 3; do
    workspace="$TEMP_DIR/workspaces/${case_id//\//-}/$replica"
    original_project="$TEMP_DIR/original/${case_id//\//-}/$replica"
    mkdir -p "$workspace" "$original_project"
    cp -R "$PROJECT_DIR/." "$workspace"
    git -C "$workspace" init --quiet
    git -C "$workspace" config user.email 'eval@example.invalid'
    git -C "$workspace" config user.name 'Evaluation fixture'
    git -C "$workspace" add .
    git -C "$workspace" commit --quiet -m 'Initial fixture'
    git_history="$(jq -r '.git_history // 1' "$EXPECTATION_FILE")"
    for commit_number in $(seq 2 "$git_history"); do
      printf '%s\n' "fixture commit $commit_number" >> "$workspace/history.txt"
      git -C "$workspace" add history.txt
      git -C "$workspace" commit --quiet -m "Fixture commit $commit_number"
    done
    if [ "$(jq -r '.feature_branch // false' "$EXPECTATION_FILE")" = true ]; then
      git -C "$workspace" switch --quiet -c feature/evaluation
    fi
    remote_url="$(jq -r '.remote_url // empty' "$EXPECTATION_FILE")"
    if [ -n "$remote_url" ]; then
      git -C "$workspace" remote add origin "$remote_url"
    fi
    if [ "$(jq -r '.preserve_user_change // false' "$EXPECTATION_FILE")" = true ]; then
      printf '%s\n' 'Uncommitted user change: preserve this content.' >> "$workspace/user-notes.md"
    fi
    cp -R "$workspace/." "$original_project"
    plugin_dir="$workspace/.claude/eval-plugin"
    mkdir -p "$plugin_dir/skills" "$plugin_dir/.claude-plugin"
    cp -R "$ROOT_DIR/skills/$SKILL" "$plugin_dir/skills/$SKILL"
    jq -n --arg skill "$SKILL" '{name: ($skill + "-eval"), version: "0.0.0", description: "Temporary evaluation plugin"}' > "$plugin_dir/.claude-plugin/plugin.json"
    response_file="$TEMP_DIR/${case_id//\//-}-$replica-response.json"
    error_file="$TEMP_DIR/${case_id//\//-}-$replica-error.txt"
    echo "Starting $case_id replica $replica/3"
    start_epoch="$(date +%s)"
    set +e
    (
      cd "$workspace"
      EVAL_CASE_NAME="$case_id" EVAL_REPLICA="$replica" "$CLAUDE_BIN" \
        -p "$(<"$PROMPT_FILE")" --model "$MODEL" --plugin-dir "$plugin_dir" \
        --output-format json --max-turns "$MAX_TURNS" --max-budget-usd "$MAX_BUDGET_USD" \
        --effort "$EFFORT" --exclude-dynamic-system-prompt-sections \
        --permission-mode acceptEdits --no-session-persistence
    ) >"$response_file" 2>"$error_file"
    exit_code=$?
    set -e
    error_category=""
    if [ "$exit_code" -ne 0 ]; then
      error_category="$(classify_provider_error "$error_file")"
      ABORT_REASON="$error_category"
    fi
    elapsed_seconds="$(( $(date +%s) - start_epoch ))"
    evidence_file="$workspace/$EVIDENCE_PATH"
    evidence_status="missing"
    if [ "$EVIDENCE_ABSENT" = true ] && [ ! -e "$evidence_file" ]; then
      evidence_status="absent"
    elif [ -f "$evidence_file" ] && { [ -z "$REQUIRED_PATTERN" ] || grep -qF -- "$REQUIRED_PATTERN" "$evidence_file"; }; then
      evidence_status="matched"
    fi
    rm -f "$evidence_file"
    rmdir "$(dirname "$evidence_file")" 2>/dev/null || true
    workspace_clean=true
    diff -qr --exclude='.claude' "$original_project" "$workspace" >/dev/null || workspace_clean=false
    cost=0
    if [ -s "$response_file" ]; then
      reported_cost="$(jq -r '.total_cost_usd // empty' "$response_file" 2>/dev/null || true)"
      [[ "$reported_cost" =~ ^[0-9]+([.][0-9]+)?$ ]] || reported_cost=0
      cost="$reported_cost"
    fi
    resolved_model="$(jq -r '.modelUsage // {} | keys[0] // empty' "$response_file" 2>/dev/null || true)"
    actual_outcome=pass
    if [ "$(jq -r '.case_kind' "$EXPECTATION_FILE")" = missing-prerequisite ]; then
      actual_outcome=blocked
    fi
    status=pass
    if [ "$exit_code" -ne 0 ] || { [ "$evidence_status" != matched ] && [ "$evidence_status" != absent ]; } || [ "$workspace_clean" != true ] || [ -z "$resolved_model" ] || [ "$actual_outcome" != "$EXPECTED_OUTCOME" ]; then
      status=fail
    fi
    echo "Finished $case_id replica $replica/3: $status (${elapsed_seconds}s)"
    jq -n --arg case_id "$case_id" --arg skill "$SKILL" --arg fixture_hash "$FIXTURE_HASH" --arg replica "$replica" --arg status "$status" --arg actual_outcome "$actual_outcome" --arg evidence_status "$evidence_status" \
      --arg resolved_model "$resolved_model" --arg workspace_clean "$workspace_clean" --arg error_category "$error_category" \
      --argjson exit_code "$exit_code" --argjson elapsed_seconds "$elapsed_seconds" --argjson cost "$cost" \
      '{case: $case_id, skill: $skill, fixture_hash: $fixture_hash, replica: ($replica | tonumber), status: $status, actual: {outcome: $actual_outcome}, deterministic_checks: {evidence_status: $evidence_status, workspace_clean: ($workspace_clean == "true")}, resolved_model: $resolved_model, exit_code: $exit_code, elapsed_seconds: $elapsed_seconds, cost_usd: $cost} + (if $error_category == "" then {} else {error_category: $error_category} end)' \
      | tee -a "$REPLICA_CHECKPOINT" >> "$case_results"
    if [ -n "$ABORT_REASON" ]; then
      echo "Aborting full evaluation: $ABORT_REASON" >&2
      break
    fi
  done

  jq -s --arg case_id "$case_id" --arg skill "$SKILL" --arg fixture_hash "$FIXTURE_HASH" --arg expected_outcome "$EXPECTED_OUTCOME" '
    {case: $case_id, fixture_hash: $fixture_hash, skill: $skill, expected: {outcome: $expected_outcome}, replicas: ., hard_check: {passed_replicas: ([.[] | select(.status == "pass")] | length), accepted: (([.[] | select(.status == "pass")] | length) >= 2)}}
  ' "$case_results" >> "$RESULTS_NDJSON"
  if [ -n "$ABORT_REASON" ]; then
    break
  fi
done

jq -s --arg model "$MODEL" --arg harness_version "$HARNESS_VERSION" --arg max_turns "$MAX_TURNS" --arg max_budget_usd "$MAX_BUDGET_USD" --arg effort "$EFFORT" --arg abort_reason "$ABORT_REASON" '
  {suite: "full", adapter: "claude-code-direct", harness: "claude-code", harness_version: $harness_version, provider: "openrouter", gateway: "anthropic-compatible", requested_model: $model, invocation: {max_turns: ($max_turns | tonumber), max_budget_usd: ($max_budget_usd | tonumber), effort: $effort, dynamic_system_prompt_sections_excluded: true}, cases: ., aggregate_cost_usd: ([.[].replicas[].cost_usd] | add), rubric: {blocking: false, status: "not-run"}, acceptance: {hard_checks_passed: ([.[].hard_check.accepted] | all)}} + (if $abort_reason == "" then {} else {aborted: {reason: $abort_reason}} end)
' "$RESULTS_NDJSON" > "$ARTIFACT_DIR/results.json"

BASELINE_CASES="$(jq '[.cases[] | {case: .case, fixture_hash: .fixture_hash, accepted: .hard_check.accepted}] | sort_by(.case)' "$ARTIFACT_DIR/results.json")"
baseline_matched=false
profile_matched=false
if jq -e --arg effort "$EFFORT" '.profile.effort == $effort and .profile.dynamic_system_prompt_sections_excluded == true' "$BASELINE" >/dev/null; then
  profile_matched=true
fi
if [ "$profile_matched" = true ] && jq -e --argjson cases "$BASELINE_CASES" '.cases | sort_by(.case) == $cases' "$BASELINE" >/dev/null; then
  baseline_matched=true
fi
baseline_status=regressed
if [ "$profile_matched" != true ]; then
  baseline_status=exploratory
elif [ "$baseline_matched" = true ]; then
  baseline_status=matched
fi
jq --arg status "$baseline_status" \
  --argjson accepted "$baseline_matched" \
  --argjson profile_matched "$profile_matched" \
  '.baseline = {status: $status, profile_matched: $profile_matched, hard_check: {all_cases_accepted: $accepted}} | .acceptance.passed = (.acceptance.hard_checks_passed and $accepted and (has("aborted") | not))' \
  "$ARTIFACT_DIR/results.json" > "$TEMP_DIR/results-with-baseline.json"
mv "$TEMP_DIR/results-with-baseline.json" "$ARTIFACT_DIR/results.json"
jq -n '{blocking: false, status: "not-configured", feedback: []}' > "$ARTIFACT_DIR/rubric.json"

if jq -e '.acceptance.passed' "$ARTIFACT_DIR/results.json" >/dev/null; then
  echo "Claude full evaluation passed: $ARTIFACT_DIR/results.json"
  exit 0
fi
echo "Claude full evaluation failed: $ARTIFACT_DIR/results.json" >&2
exit 1
