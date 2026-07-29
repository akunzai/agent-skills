#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/github-epic"

fail() {
  echo "github-epic content check failed: $*" >&2
  exit 1
}

[ -d "$SKILL_DIR" ] || fail "skills/github-epic directory is missing"

grep -q '^name: github-epic$' "$SKILL_DIR/SKILL.md" \
  || fail "SKILL.md frontmatter must use name: github-epic"

grep -q -E 'Use ONLY when .*GitHub' "$SKILL_DIR/SKILL.md" \
  || fail "description must restrict usage to GitHub hosted repositories"

grep -R -q -E 'git remote get-url origin' "$SKILL_DIR" \
  || fail "preflight hosting check guidance is missing"

[ -f "$SKILL_DIR/references/hosting-detection.md" ] \
  || fail "references/hosting-detection.md is missing"

grep -R -q -E 'hosting-detection\.md' "$SKILL_DIR/SKILL.md" \
  || fail "link to references/hosting-detection.md in SKILL.md is missing"

grep -R -q -E 'gh api .*sub_issues' "$SKILL_DIR" \
  || fail "native sub-issue API guidance is missing"

grep -R -q -E 'gh api .*blocked_by' "$SKILL_DIR" \
  || fail "blocked-by dependency API guidance is missing"

grep -R -q -E 'Part of #N|Closes #N' "$SKILL_DIR" \
  || fail "issue linking convention guidance is missing"

echo "github-epic content checks passed"
