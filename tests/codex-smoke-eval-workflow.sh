#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/codex-smoke-eval.yml"

fail() {
  echo "codex smoke workflow check failed: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "workflow is missing"
grep -q '^  workflow_dispatch:' "$WORKFLOW" || fail "workflow must be manually dispatched"
grep -q 'default: openai/gpt-5.6-luna' "$WORKFLOW" || fail "workflow must default to the Codex comparison model"
grep -q 'default: medium' "$WORKFLOW" || fail "workflow must default to medium effort"
# shellcheck disable=SC2016
grep -q 'OPENROUTER_API_KEY: \${{ secrets.OPENROUTER_API_KEY }}' "$WORKFLOW" || fail "workflow must use the protected OpenRouter secret"
grep -q 'evals/run-codex-smoke.sh' "$WORKFLOW" || fail "workflow must run the Codex smoke adapter"
grep -q 'apt-get install --yes apparmor-profiles apparmor-utils bubblewrap' "$WORKFLOW" \
  || fail "workflow must install the Codex Linux sandbox prerequisites"
grep -q '/usr/share/apparmor/extra-profiles/bwrap-userns-restrict' "$WORKFLOW" \
  || fail "workflow must use Ubuntu 24.04's packaged bwrap AppArmor profile"
grep -q 'apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict' "$WORKFLOW" \
  || fail "workflow must load the bwrap AppArmor profile"
grep -q 'retention-days: 30' "$WORKFLOW" || fail "workflow artifacts must have limited retention"

echo "codex smoke workflow checks passed"
