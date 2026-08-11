#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/api-paired-eval.yml"
RENDERER="$ROOT_DIR/evals/render-api-paired-distributions.sh"

fail() {
  echo "api paired evaluation workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "manual API evaluation workflow is missing"
[ -x "$RENDERER" ] || fail "lift distribution renderer must be executable"
grep -q '^  workflow_dispatch:' "$WORKFLOW" \
  || fail "workflow must be manually dispatched"
if grep -qE '^  (push|pull_request|schedule|release|workflow_call):' "$WORKFLOW"; then
  fail "manual API evaluation must not be automatically or reusable-triggered"
fi

grep -qE '^(  )?permissions:' "$WORKFLOW" || fail "workflow must declare permissions"
grep -q 'contents: read' "$WORKFLOW" || fail "workflow must use read-only contents permission"
grep -q 'environment: skills-evals' "$WORKFLOW" \
  || fail "workflow must use the skills-evals environment for the credential"
if grep -q "if: github.ref == 'refs/heads/main'" "$WORKFLOW"; then
  fail "workflow must not hard-code a main-ref execution guard"
fi
if grep -qE 'required_reviewers|environment_unprotected|Verify protected environment policy|deployment-branch-policies' "$WORKFLOW"; then
  fail "manual workflow must not gate execution on environment reviewers or branch policy"
fi
grep -q 'concurrency:' "$WORKFLOW" || fail "workflow must serialize live evaluation runs"
grep -q 'cancel-in-progress: false' "$WORKFLOW" \
  || fail "workflow must not cancel a live paid evaluation"
grep -q 'timeout-minutes: 360' "$WORKFLOW" \
  || fail "workflow timeout must accommodate the bounded retry matrix"

grep -q '^      target_models:' "$WORKFLOW" || fail "workflow must expose target_models"
grep -q "default: openai/gpt-5.6-luna,x-ai/grok-4.5,google/gemini-3.6-flash" \
  "$WORKFLOW" || fail "workflow must preserve the default target model set"
grep -q '^      judge_model:' "$WORKFLOW" || fail "workflow must expose judge_model"
grep -q 'default: anthropic/claude-sonnet-5' "$WORKFLOW" \
  || fail "workflow must preserve the #84 judge default"
grep -q '^      replicate_count:' "$WORKFLOW" || fail "workflow must expose replicate_count"
grep -A4 '^      replicate_count:' "$WORKFLOW" | grep -q "default: '5'" \
  || fail "workflow must default to 5 replicates"
grep -q 'replicate_count < 5' "$WORKFLOW" \
  || fail "manual workflow must enforce at least 5 replicates"
# shellcheck disable=SC2016
grep -q -- '--replicate-count "$REPLICATE_COUNT"' "$WORKFLOW" \
  || fail "workflow must snapshot replicate_count in the profile"
grep -q 'target_count \* replicate_count \* 4' "$WORKFLOW" \
  || fail "workflow request accounting must include every replicate"
grep -q 'max_attempts=3' "$WORKFLOW" \
  || fail "workflow must record the fixed retry ceiling"
# shellcheck disable=SC2016
grep -q 'request_ceiling_count=$((request_count \* max_attempts))' "$WORKFLOW" \
  || fail "workflow must account for the bounded retry ceiling"
if grep -qE '^      max_budget_usd:|MAX_BUDGET_USD|Enforce reported cost budget|budget-failure|budget_exceeded|cost_unreported|cost_invalid|cost_unavailable' "$WORKFLOW"; then
  fail "workflow must delegate spend enforcement to the OpenRouter account budget"
fi

# shellcheck disable=SC2016
[ "$(grep -cF 'OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}' "$WORKFLOW")" -eq 1 ] \
  || fail "workflow must inject the environment-scoped OpenRouter secret exactly once"
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
grep -q 'timeout --signal=TERM --kill-after=30s 350m' "$WORKFLOW" \
  || fail "runner timeout must accommodate the bounded retry matrix"
grep -q 'code: "request_timeout"' "$WORKFLOW" \
  || fail "workflow timeout must emit a typed request_timeout artifact"
grep -q 'Summarize API evaluation' "$WORKFLOW" \
  || fail "workflow must expose a human-readable manual-run summary"
grep -q 'GITHUB_STEP_SUMMARY' "$WORKFLOW" \
  || fail "workflow must write manual-run diagnostics to the step summary"
grep -q 'router_metadata' "$WORKFLOW" \
  || fail "workflow summary must expose bounded router diagnostics"
grep -q '(.pairs | type) == "array"' "$WORKFLOW" \
  || fail "workflow summary must handle failure artifacts without pairs"
grep -q '(.lift_distributions | type) == "array"' "$RENDERER" \
  || fail "workflow summary must consume per-model lift distributions"
grep -q '| Target | Samples | Scored | Not scored | Median | Min | Max | Sign consistent |' \
  "$RENDERER" || fail "workflow summary must present every distribution field"
grep -q '\.lift_distributions\[\]' "$WORKFLOW" \
  && fail "workflow must delegate distribution rendering to the tested seam"
grep -q 'evals/render-api-paired-distributions.sh' "$WORKFLOW" \
  || fail "workflow must invoke the tested distribution renderer"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
jq -n '{lift_distributions: [
  {target_model: "positive", sample_count: 2, scored_sample_count: 2,
   not_scored_sample_count: 0, median: 15, min: 10, max: 20,
   sign_consistent: true, samples: [
     {replicate_index: 1, status: "scored", treatment_score: 60,
      control_score: 50, treatment_minus_control: 10},
     {replicate_index: 2, status: "scored", treatment_score: 70,
      control_score: 50, treatment_minus_control: 20}]},
  {target_model: "negative", sample_count: 2, scored_sample_count: 2,
   not_scored_sample_count: 0, median: -15, min: -20, max: -10,
   sign_consistent: true, samples: []},
  {target_model: "mixed", sample_count: 3, scored_sample_count: 3,
   not_scored_sample_count: 0, median: 0, min: -10, max: 10,
   sign_consistent: false, samples: []},
  {target_model: "partial", sample_count: 2, scored_sample_count: 1,
   not_scored_sample_count: 1, median: 5, min: 5, max: 5,
   sign_consistent: true, samples: [
     {replicate_index: 1, status: "scored", treatment_score: 55,
      control_score: 50, treatment_minus_control: 5},
     {replicate_index: 2, status: "not-scored", treatment_score: 40,
      control_score: 50, treatment_minus_control: null}]}
]}' >"$TEST_DIR/results.json"
"$RENDERER" "$TEST_DIR/results.json" >"$TEST_DIR/summary.md"
# shellcheck disable=SC2016
grep -qF '| `positive` | 2 | 2 | 0 | 15 | 10 | 20 | true |' "$TEST_DIR/summary.md" \
  || fail "renderer must summarize positive lifts"
# shellcheck disable=SC2016
grep -qF '| `negative` | 2 | 2 | 0 | -15 | -20 | -10 | true |' "$TEST_DIR/summary.md" \
  || fail "renderer must summarize negative lifts"
# shellcheck disable=SC2016
grep -qF '| `mixed` | 3 | 3 | 0 | 0 | -10 | 10 | false |' "$TEST_DIR/summary.md" \
  || fail "renderer must summarize mixed-sign lifts"
# shellcheck disable=SC2016
grep -qF '| `partial` | 2 | 1 | 1 | 5 | 5 | 5 | true |' "$TEST_DIR/summary.md" \
  || fail "renderer must summarize partially not-scored lifts"
# shellcheck disable=SC2016
grep -qF '| `partial` | 2 | not-scored | 40 | 50 | - |' "$TEST_DIR/summary.md" \
  || fail "renderer must preserve individual not-scored samples"
grep -q '::error title=' "$WORKFLOW" \
  || fail "workflow must annotate actionable manual-run failures"
grep -A2 'Summarize API evaluation' "$WORKFLOW" \
  | grep -q 'if: always()' \
  || fail "workflow summary must run after typed failures"

grep -q 'actions/upload-artifact@v7' "$WORKFLOW" \
  || fail "workflow must upload normalized diagnostics"
grep -A4 'Upload API evaluation artifacts' "$WORKFLOW" \
  | grep -q 'if: always()' \
  || fail "workflow must upload artifacts after typed failures"
grep -q 'retention-days: 30' "$WORKFLOW" \
  || fail "workflow artifacts must have limited retention"
grep -q 'github.run_id' "$WORKFLOW" \
  || fail "workflow artifact names must identify the run"
if grep -q 'continue-on-error' "$WORKFLOW"; then
  fail "manual evaluation failures must remain visible"
fi

echo "api paired evaluation workflow checks passed"
