#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/claude-full-eval.yml"

fail() {
  echo "claude full workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "manual workflow is missing"
grep -q 'workflow_dispatch:' "$WORKFLOW" || fail "workflow must be manually dispatched"
if grep -qE '^  (push|pull_request|schedule):' "$WORKFLOW"; then
  fail "workflow must not run on push, pull requests, or a schedule"
fi
grep -q 'contents: read' "$WORKFLOW" || fail "workflow must use read-only contents permission"
grep -q 'environment: skills-evals' "$WORKFLOW" || fail "workflow must use the protected environment"
# shellcheck disable=SC2016
grep -q 'OPENROUTER_API_KEY: \${{ secrets.OPENROUTER_API_KEY }}' "$WORKFLOW" \
  || fail "workflow must read the OpenRouter key from the environment secret"
grep -q 'evals/run-claude-full.sh' "$WORKFLOW" || fail "workflow must run the full-suite seam"
grep -q 'default: medium' "$WORKFLOW" || fail "workflow must default to medium effort"
grep -q "default: '16'" "$WORKFLOW" || fail "workflow must default to 16 max turns"
# shellcheck disable=SC2016
grep -q -- '--effort "$EFFORT"' "$WORKFLOW" || fail "workflow must pass the selected effort"
grep -A2 'Upload evaluation artifacts' "$WORKFLOW" | grep -q 'if: always()' \
  || fail "workflow must upload checkpoints after cancellation"
grep -q 'retention-days: 30' "$WORKFLOW" || fail "workflow must retain diagnostics for 30 days"

echo "claude full workflow checks passed"
