#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/claude-smoke-eval.yml"

fail() {
  echo "claude smoke workflow check failed: $*" >&2
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
grep -q 'ANTHROPIC_BASE_URL: https://openrouter.ai/api' "$WORKFLOW" \
  || fail "workflow must use OpenRouter's Anthropic endpoint"
grep -q 'evals/run-claude-smoke.sh' "$WORKFLOW" || fail "workflow must run the public eval seam"
grep -q 'actions/setup-node@v7' "$WORKFLOW" || fail "workflow must use the current Node setup action"
grep -q 'node-version: lts/\*' "$WORKFLOW" || fail "workflow must use the Node LTS channel"
grep -q 'actions/upload-artifact@v7' "$WORKFLOW" || fail "workflow must upload redacted artifacts"

echo "claude smoke workflow checks passed"
