#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/agents-md"
OLD_SKILL_DIR="$ROOT_DIR/skills/agents-md-improver"

fail() {
  echo "agents-md name check failed: $*" >&2
  exit 1
}

[ -d "$SKILL_DIR" ] || fail "skills/agents-md directory is missing"
[ ! -e "$OLD_SKILL_DIR" ] || fail "old skills/agents-md-improver directory must be removed"

grep -q '^name: agents-md$' "$SKILL_DIR/SKILL.md" \
  || fail "SKILL.md frontmatter must use name: agents-md"

if git -C "$ROOT_DIR" grep -n 'agents-md-improver' -- README.md skills .github/workflows tests/agents-md-content.sh; then
  fail "tracked references to old agents-md-improver slug remain"
fi

echo "agents-md name checks passed"
