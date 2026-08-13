#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/backfill-unit-tests"
SKILL="$SKILL_DIR/SKILL.md"
GOOD_TESTS="$SKILL_DIR/references/good-tests.md"

fail() {
  echo "backfill-unit-tests content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/backfill-unit-tests/SKILL.md is missing"

grep -q '^name: backfill-unit-tests$' "$SKILL" \
  || fail "frontmatter must use name: backfill-unit-tests"

grep -q -E '^description: >-' "$SKILL" \
  || fail "description must be present"

grep -q -E 'Use when' "$SKILL" \
  || fail "description should start triggers with 'Use when'"

grep -q --fixed-strings 'tdd skill' "$SKILL" \
  || fail "cross-reference to the tdd skill is missing"

grep -q -E 'Unit tests only' "$SKILL" \
  || fail "unit-test-only scope statement is missing"

grep -q -E 'Integration, end-to-end, browser, and performance' "$SKILL" \
  || fail "explicit exclusion of integration/e2e/browser/performance tests is missing"

grep -q -E 'stop and report' "$SKILL" \
  || fail "missing-test-infrastructure stop-and-report rule is missing"

grep -q -E 'single module or a single PR' "$SKILL" \
  || fail "scope-decision threshold (single module/PR) is missing"

grep -q -E 'coverage target|coverage report' "$SKILL" \
  || fail "coverage-target mode guidance is missing"

grep -q -E 'up to 2 attempts|2 attempts' "$SKILL" \
  || fail "retry cap of 2 attempts is missing"

grep -q --fixed-strings '**Build**' "$SKILL" \
  || fail "build quality gate is missing"

grep -q -E 'test-run command finds|Discoverable' "$SKILL" \
  || fail "CI-discoverability quality gate is missing"

grep -q -E 'Mutation-lite|mutation' "$SKILL" \
  || fail "mutation-lite quality gate is missing"

grep -q -E 'No seam to test through' "$SKILL" \
  || fail "untestable-gap skip rule (no seam, don't refactor) is missing"

grep -q -E "don't refactor" "$SKILL" \
  || fail "don't-refactor-to-add-a-seam rule is missing"

grep -q -E 'reveals a bug' "$SKILL" \
  || fail "bug-discovered skip rule is missing"

grep -q -E "don't fix it" "$SKILL" \
  || fail "don't-fix-bugs-here rule is missing"

grep -q -E 'Report every skip' "$SKILL" \
  || fail "skip-reporting rule is missing"

grep -q -E 'not absolute bans' "$SKILL" \
  || fail "explicit-user-request override for bug fixes/refactoring is missing"

[ -f "$GOOD_TESTS" ] || fail "references/good-tests.md is missing"

grep -q -E 'system boundaries' "$GOOD_TESTS" \
  || fail "mock-only-at-system-boundaries guidance is missing from good-tests.md"

grep -q -E 'tautolog' "$GOOD_TESTS" \
  || fail "no-tautological-assertions guidance is missing from good-tests.md"

echo "backfill-unit-tests content checks passed"
