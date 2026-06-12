#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/tidy-commits"

fail() {
  echo "tidy-commits content check failed: $*" >&2
  exit 1
}

[ -d "$SKILL_DIR" ] || fail "skills/tidy-commits directory is missing"

grep -q '^name: tidy-commits$' "$SKILL_DIR/SKILL.md" \
  || fail "SKILL.md frontmatter must use name: tidy-commits"

grep -q -E 'Use when .*commit history|Use when .*commit stack|Use when .*fixup|Use when .*squash' "$SKILL_DIR/SKILL.md" \
  || fail "description must trigger on commit history cleanup"

grep -R -q -E 'git status|working tree' "$SKILL_DIR" \
  || fail "working tree preflight guidance is missing"

grep -R -q -E 'backup (ref|branch|tag)|backup-before' "$SKILL_DIR" \
  || fail "backup ref guidance is missing"

grep -R -q -E 'fixup|squash|reword|reorder|drop' "$SKILL_DIR" \
  || fail "commit tidy operations are missing"

grep -R -q -E 'non-interactive|GIT_SEQUENCE_EDITOR' "$SKILL_DIR" \
  || fail "non-interactive rebase guidance is missing"

grep -R -q -E 'reset --soft' "$SKILL_DIR" \
  || fail "collapse-all reset --soft shortcut is missing"

grep -R -q -E 'diff .*backup|tree.*identical|final tree' "$SKILL_DIR" \
  || fail "tree-equivalence verification guidance is missing"

grep -R -q -E -- '--update-refs|stacked branch|checked out in another worktree' "$SKILL_DIR" \
  || fail "stacked branch/update-refs guidance is missing"

grep -R -q -E 'force-with-lease|never plain --force' "$SKILL_DIR" \
  || fail "safe force push guidance is missing"

grep -R -q -E 'sign|signature|verified' "$SKILL_DIR" \
  || fail "commit signing guidance is missing"

echo "tidy-commits content checks passed"
