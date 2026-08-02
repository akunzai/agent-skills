#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/evals/run-grok-smoke.sh"
FIXTURES="$ROOT_DIR/evals/fixtures/agents-md"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "grok smoke eval check failed: $*" >&2
  exit 1
}

FAKE_GROK="$TEMP_DIR/grok"
NO_RG_DIR="$TEMP_DIR/no-rg"
mkdir -p "$NO_RG_DIR"
cat >"$NO_RG_DIR/rg" <<'EOF'
#!/usr/bin/env bash
echo "rg must not be required by the portable eval runner" >&2
exit 99
EOF
chmod +x "$NO_RG_DIR/rg"
cat >"$FAKE_GROK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "version" ]; then
  printf '%s\n' 'grok 0.2.118 (testbuild) [stable]'
  exit 0
fi

if [ "${1:-}" = "inspect" ]; then
  case " $* " in
    *" --json "*) ;;
    *) echo "missing inspect --json" >&2; exit 20 ;;
  esac
  [ -f .agents/skills/agents-md/SKILL.md ] || { echo "missing project skill" >&2; exit 21; }
  [ -f AGENTS.md ] || [ -f Agents.md ] || { echo "missing project AGENTS.md" >&2; exit 22; }
  cat <<'JSON'
{
  "grokVersion": "0.2.118",
  "channel": "stable",
  "cwd": ".",
  "projectRoot": ".",
  "projectInstructions": [
    {
      "path": "./AGENTS.md",
      "scope": "project",
      "fileType": "agents_md",
      "sizeBytes": 10,
      "approxTokens": 2
    }
  ],
  "skills": [
    {
      "name": "agents-md",
      "description": "Create, audit, and maintain AGENTS.md",
      "source": {
        "type": "project",
        "path": "./.agents/skills/agents-md/SKILL.md"
      },
      "userInvocable": true
    }
  ]
}
JSON
  exit 0
fi

prompt=""
model=""
output_format=""
always_approve=false
max_turns=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--single)
      prompt="${2:-}"
      shift 2
      ;;
    -m|--model)
      model="${2:-}"
      shift 2
      ;;
    --output-format)
      output_format="${2:-}"
      shift 2
      ;;
    --always-approve|--yolo)
      always_approve=true
      shift
      ;;
    --max-turns)
      max_turns="${2:-}"
      shift 2
      ;;
    --no-memory|--disable-web-search|--no-auto-update)
      shift
      ;;
    --permission-mode)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[ -n "$prompt" ] || { echo "missing headless prompt" >&2; exit 3; }
[ "$output_format" = "json" ] || { echo "missing json output format" >&2; exit 4; }
[ "$always_approve" = true ] || { echo "missing always-approve" >&2; exit 5; }
[ -n "$max_turns" ] || { echo "missing max-turns" >&2; exit 6; }
[ -n "$model" ] || { echo "missing model" >&2; exit 7; }
[ -f .agents/skills/agents-md/SKILL.md ] || { echo "missing project skill registration" >&2; exit 8; }
[ -d .git ] || { echo "missing isolated workspace repository" >&2; exit 9; }
[ -n "${GROK_HOME:-}" ] || { echo "missing isolated GROK_HOME" >&2; exit 10; }
[ -f "${GROK_HOME}/config.toml" ] || { echo "missing isolated config.toml" >&2; exit 11; }
grep -q 'auto_update = false' "${GROK_HOME}/config.toml" || { echo "auto_update must be disabled" >&2; exit 12; }
[ "${GROK_DISABLE_AUTOUPDATER:-}" = "1" ] || { echo "GROK_DISABLE_AUTOUPDATER must be 1" >&2; exit 13; }

case_name="${EVAL_CASE_NAME:?missing EVAL_CASE_NAME}"
provider="${EVAL_PROVIDER:?missing EVAL_PROVIDER}"
if [ "$provider" = "openrouter" ]; then
  [ -n "${OPENROUTER_API_KEY:-}" ] || { echo "missing OPENROUTER_API_KEY" >&2; exit 14; }
  grep -Fq 'openrouter.ai/api/v1' "${GROK_HOME}/config.toml" || { echo "missing OpenRouter base_url" >&2; exit 15; }
  grep -Fq 'env_key = "OPENROUTER_API_KEY"' "${GROK_HOME}/config.toml" || { echo "missing OpenRouter env_key" >&2; exit 16; }
elif [ "$provider" = "direct-xai" ]; then
  [ -n "${XAI_API_KEY:-}" ] || { echo "missing XAI_API_KEY" >&2; exit 17; }
  grep -Fq 'api.x.ai' "${GROK_HOME}/config.toml" || { echo "missing direct xAI base_url" >&2; exit 18; }
else
  echo "unsupported provider: $provider" >&2
  exit 19
fi

if [ "${FAKE_PROVIDER_FAILURE_CASE:-}" = "$case_name" ]; then
  printf '%s\n' '{"type":"error","message":"Unauthorized (401) Authorization: Bearer sk-or-v1-test-secret"}'
  echo 'Error: Unauthorized (401) Authorization: Bearer sk-or-v1-test-secret' >&2
  exit 1
fi
if [ "${FAKE_MALFORMED_CASE:-}" = "$case_name" ]; then
  printf '%s\n' 'not json'
  exit 0
fi

case "$case_name" in
  expected-trigger)
    mkdir -p evaluation
    printf '%s\n' '## Micromanagement Audit' >evaluation/quality-report.md
    ;;
  expected-non-trigger) ;;
  *)
    echo "unexpected case: $case_name" >&2
    exit 23
    ;;
esac

printf '%s\n' '{"text":"ok","stopReason":"end_turn","sessionId":"eval-session","num_turns":2,"usage":{"input_tokens":11,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":4,"reasoning_tokens":0,"total_tokens":15},"modelUsage":{"x-ai/grok-4.5":{"inputTokens":11,"outputTokens":4,"cacheReadInputTokens":0,"modelCalls":2,"costUSD":0.0012}},"total_cost_usd":0.0012}'
EOF
chmod +x "$FAKE_GROK"

[ -x "$RUNNER" ] || fail "runner is missing or not executable"
[ -L "$FIXTURES/expected-trigger/project/CLAUDE.md" ] \
  || fail "expected-trigger fixture must opt into Claude Code compatibility"
[ "$(readlink "$FIXTURES/expected-trigger/project/CLAUDE.md")" = "AGENTS.md" ] \
  || fail "expected-trigger fixture must link CLAUDE.md to AGENTS.md"

ARTIFACT_DIR="$TEMP_DIR/artifacts"
PATH="$NO_RG_DIR:$PATH" \
  OPENROUTER_API_KEY='test-openrouter-key' \
  GROK_BIN="$FAKE_GROK" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$ARTIFACT_DIR" \
  --model 'x-ai/grok-4.5' \
  --provider openrouter \
  --max-turns 8

RESULTS="$ARTIFACT_DIR/results.json"
[ -f "$RESULTS" ] || fail "normalized results were not written"
jq -e '
  .suite == "smoke"
  and .adapter == "grok-build-native"
  and .harness == "grok-build"
  and (.harness_version | test("0\\.2\\.118"))
  and .provider == "openrouter"
  and .gateway == "openrouter-chat-completions"
  and .credential_state == "present"
  and .requested_model == "x-ai/grok-4.5"
  and .discovery.project_instructions_found == true
  and .discovery.agents_md_skill_found == true
  and .discovery.skill_source == "project"
  and .auto_update_disabled == true
  and (.cases | length == 2)
  and ([.cases[].case] | sort == ["expected-non-trigger", "expected-trigger"])
  and ([.cases[].status] | all(. == "pass"))
  and ([.cases[].resolved_model] | all(. == "x-ai/grok-4.5"))
  and ([.cases[].cost_usd] | all(. == 0.0012))
  and ([.cases[].elapsed_seconds] | all(. >= 0))
  and ([.cases[].evidence.status] | sort == ["absent", "matched"])
  and ([.cases[].workspace_clean] | all(. == true))
' "$RESULTS" >/dev/null || fail "results do not satisfy the public contract"

MISSING_CREDENTIAL_ARTIFACT_DIR="$TEMP_DIR/missing-credential-artifacts"
if PATH="$NO_RG_DIR:$PATH" \
  OPENROUTER_API_KEY='' \
  GROK_BIN="$FAKE_GROK" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$MISSING_CREDENTIAL_ARTIFACT_DIR" \
  --provider openrouter; then
  fail "missing OpenRouter credential must fail before starting cases"
fi

DIRECT_ARTIFACT_DIR="$TEMP_DIR/direct-artifacts"
PATH="$NO_RG_DIR:$PATH" \
  XAI_API_KEY='test-xai-key' \
  GROK_BIN="$FAKE_GROK" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$DIRECT_ARTIFACT_DIR" \
  --provider direct-xai \
  --model 'grok-4.5'
jq -e '
  .provider == "xai"
  and .gateway == "xai-direct"
  and .credential_state == "present"
  and .requested_model == "grok-4.5"
  and ([.cases[].status] | all(. == "pass"))
' "$DIRECT_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "direct xAI provider must use the xAI gateway contract"

MALFORMED_ARTIFACT_DIR="$TEMP_DIR/malformed-artifacts"
if PATH="$NO_RG_DIR:$PATH" \
  OPENROUTER_API_KEY='test-openrouter-key' \
  FAKE_MALFORMED_CASE=expected-trigger \
  GROK_BIN="$FAKE_GROK" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$MALFORMED_ARTIFACT_DIR"; then
  fail "malformed adapter output must fail the smoke evaluation"
fi
jq -e '
  (.cases | length) == 2
  and .cases[0].error_category == "adapter_output_invalid"
  and .cases[0].error_diagnostics.response_state == "invalid_json"
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
  GROK_BIN="$FAKE_GROK" \
  "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$PROVIDER_FAILURE_ARTIFACT_DIR" >"$PROVIDER_FAILURE_LOG" 2>&1; then
  fail "provider configuration failure must fail the smoke evaluation"
fi
jq -e '
  (.cases | length) == 2
  and .cases[0].error_category == "harness_failed"
  and .cases[0].error_diagnostics.stderr_state == "nonempty"
  and .cases[0].error_diagnostics.stderr_category == "authentication_rejected"
  and (.cases[0].error_diagnostics.stderr_fingerprint | startswith("sha256:"))
' "$PROVIDER_FAILURE_ARTIFACT_DIR/results.json" >/dev/null \
  || fail "provider failures must have redacted actionable diagnostics"
if rg -n 'sk-or-v1-test-secret|Unauthorized \(401\)' \
  "$PROVIDER_FAILURE_ARTIFACT_DIR" "$PROVIDER_FAILURE_LOG"; then
  fail "artifacts and command output must not retain raw provider stderr"
fi

if GROK_BIN="$FAKE_GROK" "$RUNNER" \
  --fixture-root "$FIXTURES" \
  --artifact-dir "$TEMP_DIR/unsupported" \
  --provider invalid; then
  fail "unsupported provider must fail before starting Grok"
fi

echo "grok smoke eval checks passed"
