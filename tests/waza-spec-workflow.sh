#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$ROOT_DIR/.github/workflows/validate-skills.yml"

fail() {
  echo "waza spec workflow check failed: $*" >&2
  exit 1
}

[ -f "$WF" ] || fail ".github/workflows/validate-skills.yml is missing"

grep -q -E 'mise run lint-skills|tests/waza-spec.sh' "$WF" \
  || fail "validate-skills.yml must run the waza spec check"

if grep -q -E 'skills-ref|agentskills\.git' "$WF"; then
  fail "validate-skills.yml must not call skills-ref"
fi

echo "waza spec workflow checks passed"
