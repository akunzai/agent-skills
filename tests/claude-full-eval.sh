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

case_name="${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}"
replica="${EVAL_REPLICA:?missing EVAL_REPLICA}"
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
  --model 'anthropic/claude-sonnet-5')"

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
  and (.cases | length == 15)
  and ([.cases[].replicas | length] | all(. == 3))
  and ([.cases[].hard_check.passed_replicas] | all(. >= 2))
  and ([.cases[].hard_check.accepted] | all(. == true))
  and .baseline.status == "matched"
  and .acceptance.passed == true
  and .rubric.blocking == false
  and ((.aggregate_cost_usd - 0.45) | fabs) < 0.000001
' "$RESULTS" >/dev/null || fail "results do not satisfy the full-suite contract"

if rg -n --hidden --glob '!results.json' 'sk-[A-Za-z0-9_-]+' "$ARTIFACT_DIR"; then
  fail "artifacts must not contain credential-shaped values"
fi

echo "claude full eval checks passed"
