#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/api-evaluation-profile.yml"

fail() {
  echo "api evaluation profile workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "workflow is missing"
grep -q '^  workflow_dispatch:' "$WORKFLOW" || fail "workflow must support manual profile validation"
grep -q '^  workflow_call:' "$WORKFLOW" || fail "workflow must expose a reusable profile contract"
grep -q '^      target_models:' "$WORKFLOW" || fail "workflow must expose target_models"
grep -q '^      judge_model:' "$WORKFLOW" || fail "workflow must expose judge_model"
[ "$(grep -c '^      replicate_count:' "$WORKFLOW")" -eq 2 ] \
  || fail "manual and reusable workflows must expose replicate_count"
grep -q 'default: openai/gpt-5.6-luna,x-ai/grok-4.6,google/gemini-3.7-flash' "$WORKFLOW" \
  || fail "workflow must use the default target model set"
grep -q 'default: anthropic/claude-sonnet-5' "$WORKFLOW" \
  || fail "workflow must use the default judge model"
grep -Fq "TARGET_MODELS: \${{ inputs.target_models }}" "$WORKFLOW" \
  || fail "workflow must pass target_models through an environment variable"
grep -Fq "JUDGE_MODEL: \${{ inputs.judge_model }}" "$WORKFLOW" \
  || fail "workflow must pass judge_model through an environment variable"
grep -Fq "REPLICATE_COUNT: \${{ inputs.replicate_count }}" "$WORKFLOW" \
  || fail "workflow must pass replicate_count through an environment variable"
grep -q -- "--target-models \"\$TARGET_MODELS\"" "$WORKFLOW" \
  || fail "workflow must pass the complete target list to the profile"
grep -q -- "--judge-model \"\$JUDGE_MODEL\"" "$WORKFLOW" \
  || fail "workflow must pass the single judge to the profile"
grep -q -- "--replicate-count \"\$REPLICATE_COUNT\"" "$WORKFLOW" \
  || fail "workflow must pass replicate_count to the profile"
grep -q 'evals/api-evaluation-profile.sh' "$WORKFLOW" \
  || fail "workflow must run the profile validator"
if grep -q 'OPENROUTER_API_KEY' "$WORKFLOW"; then
  fail "profile validation workflow must not use model credentials"
fi

echo "api evaluation profile workflow checks passed"
