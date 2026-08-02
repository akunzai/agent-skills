#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/evals/run-claude-full.sh"
FIXTURES="$ROOT_DIR/evals/fixtures/full"
BASELINE="$ROOT_DIR/evals/baselines/claude-full-v1.json"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "claude full eval check failed: $*" >&2
  exit 1
}

FAKE_CLAUDE="$TEMP_DIR/claude"
cat >"$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ]; then
  printf '%s\n' '2.1.220'
  exit 0
fi

case " ${*} " in
  *" --plugin-dir "*) ;;
  *) echo "missing plugin directory" >&2; exit 3 ;;
esac
case " ${*} " in
  *" --effort medium "*|*" --effort high "*) ;;
  *) echo "missing effort setting" >&2; exit 4 ;;
esac
case " ${*} " in
  *" --exclude-dynamic-system-prompt-sections "*) ;;
  *) echo "missing cache-friendly system prompt setting" >&2; exit 5 ;;
esac

case_name="${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}"
replica="${EVAL_REPLICA:?missing EVAL_REPLICA}"
if [ -n "${FAKE_INVOCATION_LOG:-}" ]; then
  printf '%s/%s\n' "$case_name" "$replica" >> "$FAKE_INVOCATION_LOG"
fi
if [ "${FAKE_PROVIDER_FAILURE_CASE:-}" = "$case_name" ] && [ "${FAKE_PROVIDER_FAILURE_REPLICA:-}" = "$replica" ]; then
  if [ -n "${FAKE_PROVIDER_FAILURE_RESPONSE:-}" ]; then
    printf '%s\n' "$FAKE_PROVIDER_FAILURE_RESPONSE"
  fi
  printf '%s\n' 'HTTP 429' >&2
  exit 1
fi
case "$case_name" in
  *expected-non-trigger|*missing-prerequisite)
    ;;
  *)
    if [ "$replica" != "3" ]; then
      mkdir -p evaluation
      case "$case_name" in
        agents-md/*) printf '%s\n' 'Micromanagement Audit' > evaluation/result.md ;;
        tidy-commits/*) printf '%s\n' '## Cleanup Plan' > evaluation/result.md ;;
        pr-workflow/*) printf '%s\n' '## Pull Request Checklist' > evaluation/result.md ;;
        *) printf '%s\n' "Completed $case_name" > evaluation/result.md ;;
      esac
    fi
    ;;
esac
printf '%s\n' '{"modelUsage":{"anthropic/claude-sonnet-5":{}},"total_cost_usd":0.01}'
EOF
chmod +x "$FAKE_CLAUDE"

[ -x "$RUNNER" ] || fail "runner is missing or not executable"
[ -f "$BASELINE" ] || fail "approved baseline is missing"

ARTIFACT_DIR="$TEMP_DIR/artifacts"
RUN_OUTPUT="$(CLAUDE_BIN="$FAKE_CLAUDE" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --baseline "$BASELINE" \
  --artifact-dir "$ARTIFACT_DIR" \
  --model 'anthropic/claude-sonnet-5' \
  --effort medium)"

grep -q 'Starting agents-md/expected-non-trigger replica 1/3' <<<"$RUN_OUTPUT" \
  || fail "runner must report replica start progress"
grep -q 'Finished tidy-commits/representative-task replica 3/3' <<<"$RUN_OUTPUT" \
  || fail "runner must report replica completion progress"

RESULTS="$ARTIFACT_DIR/results.json"
[ -f "$RESULTS" ] || fail "normalized results were not written"
[ -f "$ARTIFACT_DIR/replicas.ndjson" ] || fail "replica checkpoint was not written"
jq -s -e 'length == 45' "$ARTIFACT_DIR/replicas.ndjson" >/dev/null \
  || fail "replica checkpoint must contain every completed replica"
jq -s -e 'all(has("case") and has("skill") and has("fixture_hash"))' "$ARTIFACT_DIR/replicas.ndjson" >/dev/null \
  || fail "replica checkpoint must identify its fixture"
[ -f "$ARTIFACT_DIR/rubric.json" ] || fail "separate rubric report was not written"
jq -e '.blocking == false and .feedback == []' "$ARTIFACT_DIR/rubric.json" >/dev/null \
  || fail "rubric report must remain non-blocking"

jq -e '
  .suite == "full"
  and .harness == "claude-code"
  and .requested_model == "anthropic/claude-sonnet-5"
  and .invocation.max_turns == 16
  and .invocation.effort == "medium"
  and .invocation.dynamic_system_prompt_sections_excluded == true
  and (.cases | length == 15)
  and ([.cases[].replicas | length] | all(. == 3))
  and ([.cases[].hard_check.passed_replicas] | all(. >= 2))
  and ([.cases[].hard_check.accepted] | all(. == true))
  and .baseline.status == "matched"
  and .baseline.profile_matched == true
  and .acceptance.passed == true
  and .rubric.blocking == false
  and ((.aggregate_cost_usd - 0.45) | fabs) < 0.000001
' "$RESULTS" >/dev/null || fail "results do not satisfy the full-suite contract"

if rg -n --hidden --glob '!results.json' 'sk-[A-Za-z0-9_-]+' "$ARTIFACT_DIR"; then
  fail "artifacts must not contain credential-shaped values"
fi

EXPLORATORY_ARTIFACT_DIR="$TEMP_DIR/exploratory-artifacts"
if CLAUDE_BIN="$FAKE_CLAUDE" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --baseline "$BASELINE" \
  --artifact-dir "$EXPLORATORY_ARTIFACT_DIR" \
  --model 'anthropic/claude-sonnet-5' \
  --effort high >/dev/null; then
  fail "exploratory effort must not pass the approved baseline"
fi
jq -e '.baseline.status == "exploratory" and .baseline.profile_matched == false and .acceptance.passed == false' \
  "$EXPLORATORY_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "exploratory result must identify its baseline mismatch"

PROVIDER_FAILURE_ARTIFACT_DIR="$TEMP_DIR/provider-failure-artifacts"
PROVIDER_FAILURE_LOG="$TEMP_DIR/provider-failure-invocations.log"
PROVIDER_FAILURE_STDERR="$TEMP_DIR/provider-failure.stderr"
if FAKE_PROVIDER_FAILURE_CASE='agents-md/expected-non-trigger' \
  FAKE_PROVIDER_FAILURE_REPLICA=2 \
  FAKE_PROVIDER_FAILURE_RESPONSE='{"type":"result","subtype":"error_during_execution","is_error":true}' \
  FAKE_INVOCATION_LOG="$PROVIDER_FAILURE_LOG" \
  CLAUDE_BIN="$FAKE_CLAUDE" "$RUNNER" \
    --fixture-root "$FIXTURES" \
    --baseline "$BASELINE" \
    --artifact-dir "$PROVIDER_FAILURE_ARTIFACT_DIR" \
    --model 'anthropic/claude-sonnet-5' \
    --effort medium >/dev/null 2>"$PROVIDER_FAILURE_STDERR"; then
  fail "provider rate limits must fail the evaluation"
fi
grep -q 'response subtype: error_during_execution' "$PROVIDER_FAILURE_STDERR" \
  || fail "structured response subtype must be reported to stderr"
EXPECTED_STDERR_SHA256="$(printf '%s\n' 'HTTP 429' | shasum -a 256 | awk '{print $1}')"
jq -s -e --arg expected_stderr_sha256 "$EXPECTED_STDERR_SHA256" '
  length == 2
  and .[1].error_category == "rate_limited"
  and .[1].error_diagnostics.stderr_bytes == 9
  and .[1].error_diagnostics.stderr_sha256 == $expected_stderr_sha256
  and .[1].error_diagnostics.response_state == "valid_json"
  and .[1].error_diagnostics.response.type == "result"
  and .[1].error_diagnostics.response.subtype == "error_during_execution"
  and .[1].error_diagnostics.response.is_error == true
' \
  "$PROVIDER_FAILURE_ARTIFACT_DIR/replicas.ndjson" >/dev/null \
  || fail "rate-limited replica must include redacted failure diagnostics"
jq -e '.aborted.reason == "rate_limited" and .acceptance.passed == false and (.cases | length == 1)' \
  "$PROVIDER_FAILURE_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "rate limits must retain partial results and abort the suite"
[ "$(wc -l < "$PROVIDER_FAILURE_LOG" | tr -d ' ')" = 2 ] \
  || fail "rate limits must stop before additional model invocations"
if rg -n 'HTTP 429' "$PROVIDER_FAILURE_ARTIFACT_DIR"; then
  fail "artifacts must not retain raw provider errors"
fi

echo "claude full eval checks passed"
