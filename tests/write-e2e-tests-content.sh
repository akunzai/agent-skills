#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/write-e2e-tests"
SKILL="$SKILL_DIR/SKILL.md"
SECURITY="$SKILL_DIR/references/security.md"
SETUP="$SKILL_DIR/references/setup.md"
CI="$SKILL_DIR/references/ci.md"
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

grep -q -E 'converting a completed webwright' "$SKILL" \
  || fail "description branch: convert a completed run is missing"

grep -q -E 'unblocking a missing' "$SKILL" \
  || fail "description branch: unblock missing toolchain/run is missing"

grep -q --fixed-strings 'API-level end-to-end' "$SKILL" \
  || fail "API-level e2e exclusion is missing"

grep -q -E 'exploration engine' "$SKILL" \
  || fail "webwright-as-exploration-engine statement is missing"

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
  || fail "Playwright Test infrastructure check is missing"

grep -q --fixed-strings 'webwright' "$SKILL" \
  || fail "webwright reference is missing"

grep -q --fixed-strings 'https://github.com/microsoft/Webwright' "$SKILL" \
  || fail "webwright repo URL is missing"

# Orchestration + confirmations (leading words, not letter codes)
grep -q --fixed-strings '**Toolchain.**' "$SKILL" \
  || fail "toolchain confirmation step is missing"

grep -q --fixed-strings '**Explore.**' "$SKILL" \
  || fail "explore confirmation step is missing"

grep -q -E 'Confirm on its own' "$SKILL" \
  || fail "explore must stay a separate confirmation"

grep -q -E 'qualifying run' "$SKILL" \
  || fail "qualifying-run detection step is missing"

grep -q -E 'reuse it' "$SKILL" \
  || fail "reuse qualifying run by default is missing"

grep -q -E 'Convert is the next step' "$SKILL" \
  || fail "auto-convert after webwright Done is missing"

grep -q -E 'Exploration stays in webwright' "$SKILL" \
  || fail "exploration must stay in webwright"

grep -q --fixed-strings '.gitignore' "$SKILL" \
  || fail "gitignore ask is missing"

grep -q --fixed-strings 'git rm --cached' "$SKILL" \
  || fail "must forbid git rm --cached"

grep -q -E 'Cypress' "$SKILL" \
  || fail "existing Cypress/Selenium coexistence rule is missing"

grep -q --fixed-strings 'references/setup.md' "$SKILL" \
  || fail "link to references/setup.md is missing"

grep -q --fixed-strings 'references/ci.md' "$SKILL" \
  || fail "link to references/ci.md is missing"

grep -q -E 'every item is marked' "$SKILL" \
  || fail "inventory completion criterion is missing"

# shellcheck disable=SC2088
grep -q -E '~/.agents/skills/webwright/SKILL.md' "$SKILL" \
  || fail "inventory must check the user-level webwright path"

grep -q --fixed-strings '<repo>/.agents/skills/webwright/SKILL.md' "$SKILL" \
  || fail "inventory must check the project-level webwright path"

grep -q -E 'loaded-skill list is not evidence' "$SKILL" \
  || fail "inventory must not treat the loaded-skill list as presence"

grep -q -E 'qualifying run from step 3 is on disk' "$SKILL" \
  || fail "explore completion must require a qualifying run on disk"

grep -q -E 'Reading source is not' "$SKILL" \
  || fail "explore must treat source-reading as not explore"

grep -q -E 'return to Explore' "$SKILL" \
  || fail "convert must return to explore when the qualifying run is missing"

# Security gates
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

if grep -q -E 'Take those files and produce|standalone Playwright' "$SKILL"; then
  fail "Convert must not frame the spec as a transcription of final_script.py"
fi

grep -q -E 'selectors and action order' "$SKILL" \
  || fail "final_script.py must be a selector/flow reference, not a transcription source"

grep -q -E 'Draft only after' "$SKILL" \
  || fail "Convert must wait for a resolved input scan before drafting"

grep -q --fixed-strings 'references/security.md' "$SKILL" \
  || fail "link to references/security.md is missing"

grep -q --fixed-strings 'scan-secrets.sh' "$SECURITY" \
  || fail "security.md must name scan-secrets.sh as the matcher"

grep -q --fixed-strings 'file:line:category' "$SECURITY" \
  || fail "security.md must describe the hit report format"

grep -q --fixed-strings 'process.env' "$SECURITY" \
  || fail "security.md must require process.env mappings"

# Setup + CI references own the scaffold / platform details
[ -f "$SETUP" ] || fail "references/setup.md is missing"
[ -f "$CI" ] || fail "references/ci.md is missing"

grep -q --fixed-strings 'npx skills add microsoft/webwright' "$SETUP" \
  || fail "setup.md must name the webwright install command"

# shellcheck disable=SC2088
grep -q -E '~/.agents/skills/webwright/SKILL.md' "$SETUP" \
  || fail "setup.md must name the user-level webwright path"

grep -q --fixed-strings 'git root (project)' "$SETUP" \
  || fail "setup.md must name the project-level webwright path"

grep -q --fixed-strings 'not satisfy webwright' "$SETUP" \
  || fail "setup.md must say Node Playwright does not satisfy webwright"

grep -q --fixed-strings 'aube add' "$SETUP" \
  || fail "setup.md must follow aube when the project uses it"

grep -q --fixed-strings 'Desktop Firefox' "$SETUP" \
  || fail "setup.md must default new config to Firefox"

grep -q --fixed-strings 'Desktop Chrome' "$SETUP" \
  || fail "setup.md must document the Chromium switch"

grep -q --fixed-strings 'playwright install firefox chromium' "$SETUP" \
  || fail "setup.md must install both browser binaries"

grep -q --fixed-strings 'Leave an existing' "$SETUP" \
  || fail "setup.md must leave an existing playwright.config"

grep -q --fixed-strings 'playwright install --with-deps' "$CI" \
  || fail "ci.md must install browsers with OS deps"

grep -q --fixed-strings 'upload-artifact' "$CI" \
  || fail "ci.md must upload the Playwright report on GitHub"

grep -q --fixed-strings 'GitHub Actions' "$CI" \
  || fail "ci.md must cover GitHub Actions"

grep -q --fixed-strings '.gitlab-ci.yml' "$CI" \
  || fail "ci.md must cover GitLab CI"

echo "write-e2e-tests content checks passed"
