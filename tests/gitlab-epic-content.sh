#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/gitlab-epic"

fail() {
  echo "gitlab-epic content check failed: $*" >&2
  exit 1
}

[ -d "$SKILL_DIR" ] || fail "skills/gitlab-epic directory is missing"

grep -q '^name: gitlab-epic$' "$SKILL_DIR/SKILL.md" \
  || fail "SKILL.md frontmatter must use name: gitlab-epic"

grep -q -E 'Use ONLY when .*GitLab' "$SKILL_DIR/SKILL.md" \
  || fail "description must restrict usage to GitLab hosted repositories"

grep -R -q -E 'git remote get-url origin' "$SKILL_DIR" \
  || fail "preflight hosting check guidance is missing"

[ -f "$SKILL_DIR/references/hosting-detection.md" ] \
  || fail "references/hosting-detection.md is missing"

grep -R -q -E 'hosting-detection\.md' "$SKILL_DIR/SKILL.md" \
  || fail "link to references/hosting-detection.md in SKILL.md is missing"

grep -R -q -E 'Premium|Ultimate|Native Epics' "$SKILL_DIR" \
  || fail "Premium/Ultimate native epics guidance is missing"

grep -R -q -E 'Free Tier|Community Edition|Free' "$SKILL_DIR" \
  || fail "Free tier / CE fallback guidance is missing"

grep -R -q -E 'Part of #|Relates to #' "$SKILL_DIR" \
  || fail "Markdown keyword fallback guidance is missing"

grep -R -q -E 'epic::|type::epic|parent::' "$SKILL_DIR" \
  || fail "Scoped label fallback guidance is missing"

echo "gitlab-epic content checks passed"
