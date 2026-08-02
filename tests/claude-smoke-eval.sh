#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/evals/run-claude-smoke.sh"
FIXTURES="$ROOT_DIR/evals/fixtures/agents-md"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "claude smoke eval check failed: $*" >&2
  exit 1
}

FAKE_CLAUDE="$TEMP_DIR/claude"
NO_RG_DIR="$TEMP_DIR/no-rg"
mkdir -p "$NO_RG_DIR"
cat >"$NO_RG_DIR/rg" <<'EOF'
#!/usr/bin/env bash
echo "rg must not be required by the portable eval runner" >&2
exit 99
EOF
chmod +x "$NO_RG_DIR/rg"
cat >"$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ]; then
  printf '%s\n' '2.1.220'
  exit 0
fi

case " $* " in
  *" --plugin-dir "*) ;;
  *)
    echo "missing plugin directory" >&2
    exit 3
    ;;
esac

case_name="${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}"
if [ "${FAKE_FAILURE_CASE:-}" = "$case_name" ]; then
  printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"OpenRouter insufficient credits"}'
  exit 1
fi
case "$case_name" in
  expected-trigger)
    mkdir -p evaluation
    printf '%s\n' '## Micromanagement Audit' > evaluation/quality-report.md
    printf '%s\n' '{"modelUsage":{"anthropic/claude-haiku-4.5":{}},"total_cost_usd":0.01}'
    ;;
  expected-non-trigger)
    printf '%s\n' '{"modelUsage":{"anthropic/claude-haiku-4.5":{}},"total_cost_usd":0.01}'
    ;;
  missing-prerequisite)
    printf '%s\n' '{"modelUsage":{"anthropic/claude-haiku-4.5":{}},"total_cost_usd":0.01}'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$FAKE_CLAUDE"

[ -x "$RUNNER" ] || fail "runner is missing or not executable"

ARTIFACT_DIR="$TEMP_DIR/artifacts"
PATH="$NO_RG_DIR:$PATH" CLAUDE_BIN="$FAKE_CLAUDE" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$ARTIFACT_DIR" \
  --model 'anthropic/claude-haiku-4.5'

RESULTS="$ARTIFACT_DIR/results.json"
[ -f "$RESULTS" ] || fail "normalized results were not written"

jq -e '
  .suite == "smoke"
  and .harness == "claude-code"
  and .requested_model == "anthropic/claude-haiku-4.5"
  and .harness_version == "2.1.220"
  and (.cases | length == 3)
  and ([.cases[].status] | all(. == "pass"))
  and ([.cases[].resolved_model] | all(. == "anthropic/claude-haiku-4.5"))
  and ([.cases[].elapsed_seconds] | all(. >= 0))
  and ([.cases[].evidence.status] | sort == ["absent", "absent", "matched"])
  and ([.cases[].workspace_clean] | all(. == true))
  and .aggregate_cost_usd == 0.03
' "$RESULTS" >/dev/null || fail "results do not satisfy the public contract"

if rg -n --hidden --glob '!results.json' 'sk-[A-Za-z0-9_-]+' "$ARTIFACT_DIR"; then
  fail "artifacts must not contain credential-shaped values"
fi

FAILURE_ARTIFACT_DIR="$TEMP_DIR/failure-artifacts"
if PATH="$NO_RG_DIR:$PATH" FAKE_FAILURE_CASE=expected-trigger CLAUDE_BIN="$FAKE_CLAUDE" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$FAILURE_ARTIFACT_DIR" \
  --model 'anthropic/claude-haiku-4.5'; then
  fail "provider failures must fail the smoke evaluation"
fi
jq -e '
  (.cases | length) == 1
  and .cases[0].error_category == "budget_exhausted"
  and .cases[0].error_diagnostics.response_state == "valid_json"
' "$FAILURE_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "smoke failures must classify response errors and stop immediately"
if rg -n 'OpenRouter insufficient credits' "$FAILURE_ARTIFACT_DIR"; then
  fail "smoke artifacts must not retain raw provider errors"
fi

# shellcheck disable=SC2016
grep -q 'path: (\$case_name + "/" + \$evidence_path)' "$RUNNER" \
  || fail "runner must use jq 1.6-compatible object-value concatenation"

echo "claude smoke eval checks passed"
