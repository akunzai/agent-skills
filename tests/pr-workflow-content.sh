#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/pr-workflow"

fail() {
  echo "pr-workflow content check failed: $*" >&2
  exit 1
}

[ -d "$SKILL_DIR" ] || fail "skills/pr-workflow directory is missing"

grep -q '^name: pr-workflow$' "$SKILL_DIR/SKILL.md" \
  || fail "SKILL.md frontmatter must use name: pr-workflow"

grep -q -E 'Use when .*pull request|Use when .*PR' "$SKILL_DIR/SKILL.md" \
  || fail "description must trigger on pull requests"

grep -R -q -E 'tests|linters' "$SKILL_DIR" \
  || fail "preflight test and lint guidance is missing"

grep -R -q -E 'GIT_EDITOR=true|--no-edit' "$SKILL_DIR" \
  || fail "non-interactive git operations guidance is missing"

grep -R -q -E 'Branch Guard|Base Discovery' "$SKILL_DIR" \
  || fail "default branch protection guidance is missing"

grep -R -q -E 'changelog|release' "$SKILL_DIR" \
  || fail "dependency bump changelog guidance is missing"

grep -R -q -E 'Closes #N|Part of #N' "$SKILL_DIR" \
  || fail "issue linking rule guidance is missing"

grep -R -q -E 'gh pr edit' "$SKILL_DIR" \
  || fail "PR update on amend guidance is missing"

[ -f "$SKILL_DIR/references/platform-tools.md" ] \
  || fail "references/platform-tools.md is missing"

grep -R -q -E 'platform-tools\.md' "$SKILL_DIR/SKILL.md" \
  || fail "link to references/platform-tools.md in SKILL.md is missing"

grep -R -q -E 'Base Sync|git fetch origin' "$SKILL_DIR" \
  || fail "Base Sync preflight guidance is missing"

echo "pr-workflow content checks passed"
