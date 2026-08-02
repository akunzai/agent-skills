#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/grok-smoke-eval.yml"

fail() {
  echo "grok smoke workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "workflow is missing"
grep -q '^  workflow_dispatch:' "$WORKFLOW" || fail "workflow must be manually dispatched"
grep -q 'default: x-ai/grok-4.5' "$WORKFLOW" || fail "workflow must default to the OpenRouter Grok 4.5 model"
grep -q 'default: openrouter' "$WORKFLOW" || fail "workflow must default to the OpenRouter provider"
# shellcheck disable=SC2016
grep -q 'OPENROUTER_API_KEY: \${{ secrets.OPENROUTER_API_KEY }}' "$WORKFLOW" \
  || fail "workflow must use the protected OpenRouter secret"
grep -q 'evals/run-grok-smoke.sh' "$WORKFLOW" || fail "workflow must run the Grok smoke adapter"
grep -q '@xai-official/grok@0.2.118' "$WORKFLOW" || fail "workflow must pin the Grok Build release"
grep -q 'GROK_DISABLE_AUTOUPDATER: .1.' "$WORKFLOW" \
  || grep -q 'GROK_DISABLE_AUTOUPDATER: "1"' "$WORKFLOW" \
  || grep -q "GROK_DISABLE_AUTOUPDATER: '1'" "$WORKFLOW" \
  || grep -q 'GROK_DISABLE_AUTOUPDATER=1' "$WORKFLOW" \
  || fail "workflow must disable automatic updates"
if grep -q 'secrets.XAI_API_KEY' "$WORKFLOW"; then
  fail "routine workflow must not inject direct xAI credentials"
fi
grep -q 'retention-days: 30' "$WORKFLOW" || fail "workflow artifacts must have limited retention"
grep -q 'environment: skills-evals' "$WORKFLOW" || fail "workflow must use the protected environment"

echo "grok smoke workflow checks passed"
