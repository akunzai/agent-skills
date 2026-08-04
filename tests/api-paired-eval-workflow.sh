#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/api-paired-eval.yml"

fail() {
  echo "api paired evaluation workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "protected API evaluation workflow is missing"
grep -q '^  workflow_dispatch:' "$WORKFLOW" \
  || fail "workflow must be manually dispatched"
if grep -qE '^  (push|pull_request|schedule|release|workflow_call):' "$WORKFLOW"; then
  fail "protected API evaluation must not be automatically or reusable-triggered"
fi

grep -qE '^(  )?permissions:' "$WORKFLOW" || fail "workflow must declare permissions"
grep -q 'contents: read' "$WORKFLOW" || fail "workflow must use read-only contents permission"
grep -q 'deployments: read' "$WORKFLOW" \
  || fail "workflow must use read-only deployment metadata permission"
grep -q 'actions: read' "$WORKFLOW" \
  || fail "workflow must use read-only environment metadata permission"
grep -q 'environment: skills-evals' "$WORKFLOW" \
  || fail "workflow must use the protected skills-evals environment"
grep -q "if: github.ref == 'refs/heads/main'" "$WORKFLOW" \
  || fail "workflow must only run credentialed code from the main ref"
grep -q 'deployment-branch-policies' "$WORKFLOW" \
  || fail "workflow must verify the environment branch policy"
grep -q 'required_reviewers' "$WORKFLOW" \
  || fail "workflow must verify required environment reviewers"
grep -q 'environment_unprotected' "$WORKFLOW" \
  || fail "workflow must fail closed when environment protection is absent"
grep -q 'concurrency:' "$WORKFLOW" || fail "workflow must serialize live evaluation runs"
grep -q 'cancel-in-progress: false' "$WORKFLOW" \
  || fail "workflow must not cancel a live paid evaluation"
grep -q 'timeout-minutes: 30' "$WORKFLOW" \
  || fail "workflow must declare a bounded job timeout"

grep -q '^      target_models:' "$WORKFLOW" || fail "workflow must expose target_models"
grep -q "default: openai/gpt-5.6-luna,x-ai/grok-4.5,google/gemini-3.6-flash" \
  "$WORKFLOW" || fail "workflow must preserve the #84 target default"
grep -q '^      judge_model:' "$WORKFLOW" || fail "workflow must expose judge_model"
grep -q 'default: anthropic/claude-sonnet-5' "$WORKFLOW" \
  || fail "workflow must preserve the #84 judge default"
grep -q '^      max_budget_usd:' "$WORKFLOW" \
  || fail "workflow must expose a bounded budget input"
grep -q "default: '1.00'" "$WORKFLOW" \
  || fail "workflow must default to a conservative budget"

# shellcheck disable=SC2016
[ "$(grep -cF 'OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}' "$WORKFLOW")" -eq 1 ] \
  || fail "workflow must inject the protected OpenRouter secret exactly once"
if grep -Eq 'echo .*[Oo][Pp][Ee][Nn][Rr][Oo][Uu][Tt][Ee][Rr]_API_KEY|OPENROUTER_API_KEY.*(artifact|upload|path)' \
  "$WORKFLOW"; then
  fail "workflow must not print or upload the OpenRouter secret"
fi

grep -q 'evals/api-evaluation-profile.sh' "$WORKFLOW" \
  || fail "workflow must snapshot the validated API profile"
grep -q 'evals/fixtures/api/agents-md/representative-task' "$WORKFLOW" \
  || fail "workflow must use the checked-in API fixture"
grep -q 'evals/run-api-paired.sh' "$WORKFLOW" \
  || fail "workflow must invoke the repository-owned paired runner"
grep -q 'timeout --signal=TERM --kill-after=30s 25m' "$WORKFLOW" \
  || fail "workflow must bound the live runner timeout"
grep -q 'code: "request_timeout"' "$WORKFLOW" \
  || fail "workflow timeout must emit a typed request_timeout artifact"
grep -q "MAX_TARGET_MODELS: '3'" "$WORKFLOW" \
  || fail "workflow must cap the target sweep"
grep -q "MAX_REQUESTS: '12'" "$WORKFLOW" \
  || fail "workflow must cap the number of provider requests"
grep -q 'MAX_BUDGET_USD' "$WORKFLOW" \
  || fail "workflow must enforce the selected budget"
grep -q 'cost_unreported' "$WORKFLOW" \
  || fail "workflow must fail closed when provider cost is unavailable"
grep -q 'cost_invalid' "$WORKFLOW" \
  || fail "workflow must reject invalid provider cost values"
grep -q 'cost_unavailable' "$WORKFLOW" \
  || fail "workflow must type cost diagnostics for non-paired failures"
grep -q 'budget_exceeded' "$WORKFLOW" \
  || fail "workflow must emit a typed budget failure"
grep -A3 'Enforce reported cost budget' "$WORKFLOW" \
  | grep -q 'if: always()' \
  || fail "workflow must retain budget diagnostics after runner failure"

grep -q 'actions/upload-artifact@v7' "$WORKFLOW" \
  || fail "workflow must upload normalized diagnostics"
grep -A4 'Upload protected API evaluation artifacts' "$WORKFLOW" \
  | grep -q 'if: always()' \
  || fail "workflow must upload artifacts after typed failures"
grep -q 'retention-days: 30' "$WORKFLOW" \
  || fail "workflow artifacts must have limited retention"
grep -q 'github.run_id' "$WORKFLOW" \
  || fail "workflow artifact names must identify the run"
if grep -q 'continue-on-error' "$WORKFLOW"; then
  fail "protected evaluation failures must fail closed"
fi

echo "api paired evaluation workflow checks passed"
