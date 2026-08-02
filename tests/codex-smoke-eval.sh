#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/evals/run-codex-smoke.sh"
FIXTURES="$ROOT_DIR/evals/fixtures/agents-md"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "codex smoke eval check failed: $*" >&2
  exit 1
}

FAKE_CODEX="$TEMP_DIR/codex"
NO_RG_DIR="$TEMP_DIR/no-rg"
mkdir -p "$NO_RG_DIR"
cat >"$NO_RG_DIR/rg" <<'EOF'
#!/usr/bin/env bash
echo "rg must not be required by the portable eval runner" >&2
exit 99
EOF
chmod +x "$NO_RG_DIR/rg"
cat >"$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ]; then
  printf '%s\n' 'codex-cli 0.146.0'
  exit 0
fi

[ "${1:-}" = exec ] || exit 2
[ -f .agents/skills/agents-md/SKILL.md ] || { echo "missing native project skill" >&2; exit 8; }
[ -d .git ] || { echo "missing isolated workspace repository" >&2; exit 17; }
prompt="${!#}"
if [ "${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}" = "expected-trigger" ]; then
  [ "${prompt#\$agents-md }" != "$prompt" ] || { echo "missing native skill invocation" >&2; exit 14; }
fi
case " $* " in
  *" --json "*) ;;
  *) echo "missing JSONL output" >&2; exit 3 ;;
esac
case " $* " in
  *" --ephemeral "*) ;;
  *) echo "missing ephemeral mode" >&2; exit 4 ;;
esac
case " $* " in
  *" --sandbox workspace-write "*) ;;
  *) echo "missing workspace-write sandbox" >&2; exit 5 ;;
esac
case " $* " in
  *" --skip-git-repo-check "*) ;;
  *) echo "missing isolated-workspace repository override" >&2; exit 13 ;;
esac
case " $* " in
  *' model_provider="openrouter" '*) ;;
  *) echo "missing OpenRouter provider" >&2; exit 9 ;;
esac
case " $* " in
  *' model_providers.openrouter.base_url="https://openrouter.ai/api/v1" '*) ;;
  *) echo "missing OpenRouter endpoint" >&2; exit 10 ;;
esac
case " $* " in
  *' model_providers.openrouter.env_key="OPENROUTER_API_KEY" '*) ;;
  *) echo "missing OpenRouter credential source" >&2; exit 11 ;;
esac
case " $* " in
  *' model_providers.openrouter.wire_api="responses" '*) ;;
  *) echo "missing Responses API protocol" >&2; exit 12 ;;
esac
case " $* " in
  *" --ask-for-approval "*) echo "unsupported approval flag" >&2; exit 7 ;;
esac

case_name="${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}"
if [ "$case_name" = "expected-trigger" ]; then
  [ -d evaluation ] || { echo "missing fixture output directory" >&2; exit 15; }
  [ -f evaluation/quality-report.md ] || { echo "missing fixture output file" >&2; exit 16; }
fi
if [ "${FAKE_PROVIDER_FAILURE_CASE:-}" = "$case_name" ]; then
  echo 'Error: unsupported wire_api: responses; Authorization: Bearer sk-or-v1-test-secret' >&2
  exit 1
fi
if [ "${FAKE_MALFORMED_CASE:-}" = "$case_name" ]; then
  printf '%s\n' 'not json'
  exit 0
fi
case "$case_name" in
  expected-trigger)
    mkdir -p evaluation
    printf '%s\n' '## Micromanagement Audit' > evaluation/quality-report.md
    ;;
  expected-non-trigger|missing-prerequisite) ;;
  *) exit 6 ;;
esac
printf '%s\n' '{"type":"thread.started","thread_id":"eval-thread"}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":4}}'
EOF
chmod +x "$FAKE_CODEX"

[ -x "$RUNNER" ] || fail "runner is missing or not executable"
[ -L "$FIXTURES/expected-trigger/project/CLAUDE.md" ] \
  || fail "expected-trigger fixture must opt into Claude Code compatibility"
[ "$(readlink "$FIXTURES/expected-trigger/project/CLAUDE.md")" = "AGENTS.md" ] \
  || fail "expected-trigger fixture must link CLAUDE.md to AGENTS.md"

ARTIFACT_DIR="$TEMP_DIR/artifacts"
PATH="$NO_RG_DIR:$PATH" OPENROUTER_API_KEY='test-openrouter-key' CODEX_BIN="$FAKE_CODEX" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$ARTIFACT_DIR" \
  --model 'openai/gpt-5.6-luna' \
  --effort medium

RESULTS="$ARTIFACT_DIR/results.json"
[ -f "$RESULTS" ] || fail "normalized results were not written"
jq -e '
  .suite == "smoke"
  and .adapter == "codex-cli-native"
  and .harness == "codex-cli"
  and .harness_version == "codex-cli 0.146.0"
  and .provider == "openrouter"
  and .gateway == "openrouter-responses"
  and .credential_state == "present"
  and .requested_model == "openai/gpt-5.6-luna"
  and .requested_effort == "medium"
  and .resolved_model == null
  and .model_resolution_status == "not-reported"
  and .aggregate_cost_usd == null
  and .aggregate_cost_status == "not-reported"
  and (.cases | length == 3)
  and ([.cases[].status] | all(. == "pass"))
  and ([.cases[].resolved_model] | all(. == null))
  and ([.cases[].cost_usd] | all(. == null))
  and ([.cases[].usage.input_tokens] | all(. == 10))
  and ([.cases[].elapsed_seconds] | all(. >= 0))
  and ([.cases[].evidence.status] | sort == ["absent", "absent", "matched"])
  and ([.cases[].workspace_clean] | all(. == true))
' "$RESULTS" >/dev/null || fail "results do not satisfy the public contract"

MISSING_CREDENTIAL_ARTIFACT_DIR="$TEMP_DIR/missing-credential-artifacts"
PATH="$NO_RG_DIR:$PATH" OPENROUTER_API_KEY='' CODEX_BIN="$FAKE_CODEX" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$MISSING_CREDENTIAL_ARTIFACT_DIR"
jq -e '.credential_state == "missing"' "$MISSING_CREDENTIAL_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "missing OpenRouter credential must be reported without its value"

MALFORMED_ARTIFACT_DIR="$TEMP_DIR/malformed-artifacts"
if PATH="$NO_RG_DIR:$PATH" \
  OPENROUTER_API_KEY='test-openrouter-key' \
  FAKE_MALFORMED_CASE=expected-trigger \
  CODEX_BIN="$FAKE_CODEX" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$MALFORMED_ARTIFACT_DIR"; then
  fail "malformed adapter output must fail the smoke evaluation"
fi
jq -e '
  (.cases | length) == 3
  and .cases[0].error_category == "adapter_output_invalid"
  and .cases[0].error_diagnostics.response_state == "invalid_jsonl"
' "$MALFORMED_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "malformed output must have safe diagnostics"
if rg -n 'not json' "$MALFORMED_ARTIFACT_DIR"; then
  fail "artifacts must not retain raw adapter output"
fi

PROVIDER_FAILURE_ARTIFACT_DIR="$TEMP_DIR/provider-failure-artifacts"
PROVIDER_FAILURE_LOG="$TEMP_DIR/provider-failure.log"
if PATH="$NO_RG_DIR:$PATH" \
  OPENROUTER_API_KEY='test-openrouter-key' \
  FAKE_PROVIDER_FAILURE_CASE=expected-trigger \
  CODEX_BIN="$FAKE_CODEX" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$PROVIDER_FAILURE_ARTIFACT_DIR" >"$PROVIDER_FAILURE_LOG" 2>&1; then
  fail "provider configuration failure must fail the smoke evaluation"
fi
jq -e '
  (.cases | length) == 3
  and .cases[0].error_category == "harness_failed"
  and .cases[0].error_diagnostics.stderr_state == "nonempty"
  and .cases[0].error_diagnostics.stderr_category == "configuration_invalid"
  and (.cases[0].error_diagnostics.stderr_fingerprint | startswith("sha256:"))
' "$PROVIDER_FAILURE_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "provider failures must have redacted actionable diagnostics"
if rg -n 'sk-or-v1-test-secret|unsupported wire_api' \
  "$PROVIDER_FAILURE_ARTIFACT_DIR" "$PROVIDER_FAILURE_LOG"; then
  fail "artifacts and command output must not retain raw provider stderr"
fi

if CODEX_BIN="$FAKE_CODEX" "$RUNNER" --fixture-root "$FIXTURES" --artifact-dir "$TEMP_DIR/unsupported" --effort invalid; then
  fail "unsupported effort must fail before starting Codex"
fi

echo "codex smoke eval checks passed"
