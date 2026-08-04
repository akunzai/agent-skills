#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "api evaluation cleanup check failed: $*" >&2
  exit 1
}

legacy_patterns=(
  '\.github/workflows/(claude-full|claude-smoke|codex-smoke|grok-smoke)-eval\.yml$'
  'docs/evals/(claude-full|claude-smoke|codex-smoke|grok-smoke)\.md$'
  'evals/baselines/claude-full'
  'evals/run-(claude-full|claude-smoke|codex-smoke|grok-smoke)\.sh$'
  'evals/fixtures/(agents-md|full)(/|$)'
  'tests/(claude-full-eval|claude-smoke-eval|codex-smoke-eval|grok-smoke-eval)(-workflow)?\.sh$'
  'eval-(claude|codex|grok)-smoke'
  '(^|/)(expected-(non-)?trigger|missing-prerequisite|pre-existing-user-change)(/|$)'
  'release-baseline|three-replica'
)

for pattern in "${legacy_patterns[@]}"; do
  if rg --files --hidden -g '!.git' "$ROOT_DIR" | rg -q "$pattern"; then
    fail "retired path still exists for pattern: $pattern"
  fi

  if rg -n --hidden -g '!.git' -g '!tests/api-eval-cleanup.sh' \
    -e "$pattern" "$ROOT_DIR"; then
    fail "stale native evaluation reference remains for pattern: $pattern"
  fi
done

grep -q --fixed-strings 'docs/evals/api-paired.md' "$ROOT_DIR/AGENTS.md" \
  || fail "AGENTS.md must point maintainers to the API-level evaluation lane"
grep -q --fixed-strings '.github/workflows/api-paired-eval.yml' "$ROOT_DIR/AGENTS.md" \
  || fail "AGENTS.md must point maintainers to the protected API workflow"
[ -x "$ROOT_DIR/evals/run-api-paired.sh" ] \
  || fail "the API paired runner must remain available"
[ -d "$ROOT_DIR/evals/fixtures/api" ] \
  || fail "API response-level fixtures must remain available"
[ -f "$ROOT_DIR/.github/workflows/api-paired-eval.yml" ] \
  || fail "the protected API workflow must remain available"

echo "API evaluation cleanup checks passed"
