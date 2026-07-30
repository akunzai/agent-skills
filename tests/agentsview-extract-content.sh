#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/agentsview-extract"
SKILL="$SKILL_DIR/SKILL.md"

fail() {
  echo "agentsview-extract content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/agentsview-extract/SKILL.md is missing"

grep -q '^name: agentsview-extract$' "$SKILL" \
  || fail "frontmatter must use name: agentsview-extract"

grep -q -E '^description:' "$SKILL" \
  || fail "description must be present"

grep -q -E 'references/security.md' "$SKILL" \
  || fail "link to references/security.md is missing"

grep -q -E 'references/agentsview-cli.md' "$SKILL" \
  || fail "link to references/agentsview-cli.md is missing"

[ -f "$SKILL_DIR/references/security.md" ] || fail "references/security.md is missing"
[ -f "$SKILL_DIR/references/agentsview-cli.md" ] || fail "references/agentsview-cli.md is missing"

echo "agentsview-extract content checks passed"
