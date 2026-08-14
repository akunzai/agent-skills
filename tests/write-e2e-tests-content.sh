#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/write-e2e-tests"
SKILL="$SKILL_DIR/SKILL.md"
SECURITY="$SKILL_DIR/references/security.md"
SCANNER="$SKILL_DIR/scripts/scan-secrets.sh"

fail() {
  echo "write-e2e-tests content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/write-e2e-tests/SKILL.md is missing"

grep -q '^name: write-e2e-tests$' "$SKILL" \
  || fail "frontmatter must use name: write-e2e-tests"

grep -q -E '^description: >-' "$SKILL" \
  || fail "description must be present"

grep -q -E 'Use when' "$SKILL" \
  || fail "description should start triggers with 'Use when'"

grep -q -E 'Browser-driven UI flows only' "$SKILL" \
  || fail "browser-UI-only scope statement is missing"

grep -q -E 'not API-level end-to-end tests' "$SKILL" \
  || fail "API-level e2e exclusion is missing"

grep -q -E 'exploration engine, unchanged' "$SKILL" \
  || fail "reuses-webwright's-workflow-unchanged statement is missing"

grep -q -E 'one-to-one to an' "$SKILL" \
  || fail "Critical-Point-to-assertion mapping rule is missing"

grep -q --fixed-strings 'Playwright Test' "$SKILL" \
  || fail "fixed Playwright Test target is missing"

grep -q -E 'no per-project detection' "$SKILL" \
  || fail "no-per-project-framework-detection statement is missing"

grep -q -E 'no cross-framework translation' "$SKILL" \
  || fail "no-cross-framework-translation statement is missing"

grep -q -E 'existing e2e test directory' "$SKILL" \
  || fail "output-file-location guidance is missing"

grep -q --fixed-strings '**Run**' "$SKILL" \
  || fail "single-run quality gate is missing"

grep -q -E '3 consecutive' "$SKILL" \
  || fail "3x stability re-run quality gate is missing"

grep -q --fixed-strings '**Discoverable**' "$SKILL" \
  || fail "CI-discoverability quality gate is missing"

grep -q -E 'up to 2 attempts' "$SKILL" \
  || fail "retry cap of 2 attempts is missing"

grep -q -E 'stop and report' "$SKILL" \
  || fail "stop-and-report rule is missing"

grep -q --fixed-strings '@playwright/test' "$SKILL" \
  || fail "missing-Playwright-Test-infrastructure check is missing"

grep -q -E 'explicit confirmation before proceeding' "$SKILL" \
  || fail "webwright-install-confirmation rule is missing"

grep -q --fixed-strings 'webwright' "$SKILL" \
  || fail "webwright reference is missing"

grep -q --fixed-strings 'https://github.com/microsoft/Webwright' "$SKILL" \
  || fail "webwright repo URL is missing"

[ -f "$SECURITY" ] || fail "references/security.md is missing"
[ -x "$SCANNER" ] || fail "scripts/scan-secrets.sh is missing or not executable"

grep -q --fixed-strings 'scripts/scan-secrets.sh' "$SKILL" \
  || fail "Convert step must require scripts/scan-secrets.sh"

grep -q --fixed-strings 'Scan input' "$SKILL" \
  || fail "input scan gate is missing"

grep -q --fixed-strings 'Scan output' "$SKILL" \
  || fail "output scan gate is missing"

grep -q --fixed-strings 'process.env' "$SKILL" \
  || fail "process.env credential writing rule is missing"

grep -q --fixed-strings 'references/security.md' "$SKILL" \
  || fail "link to references/security.md is missing"

grep -q --fixed-strings 'scan-secrets.sh' "$SECURITY" \
  || fail "security.md must name scan-secrets.sh as the matcher"

grep -q --fixed-strings 'file:line:category' "$SECURITY" \
  || fail "security.md must describe the hit report format"

grep -q --fixed-strings 'process.env' "$SECURITY" \
  || fail "security.md must require process.env mappings"

grep -q --fixed-strings 'Claude Code skill' "$SKILL" \
  || fail "webwright-is-itself-a-skill clarification is missing"

echo "write-e2e-tests content checks passed"
