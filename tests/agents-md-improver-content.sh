#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/agents-md-improver"

fail() {
  echo "agents-md-improver content check failed: $*" >&2
  exit 1
}

if grep -R -n --fixed-strings 'ln -sf AGENTS.md CLAUDE.md' "$SKILL_DIR"; then
  fail "docs must not recommend force-replacing CLAUDE.md with ln -sf"
fi

if grep -R -n -E 'Use TypeScript for all new code|Vanilla CSS|HSL variables|component files under 200 lines' "$SKILL_DIR/references/templates.md"; then
  fail "starter template must not include framework-specific rules without repo evidence"
fi

grep -R -q -E 'If `?CLAUDE\.md`? already exists and is not the intended symlink' "$SKILL_DIR" \
  || fail "safe CLAUDE.md migration rule is missing"

grep -R -q -E 'Choose the target `?AGENTS\.md`? explicitly' "$SKILL_DIR" \
  || fail "multi-AGENTS target selection rule is missing"

echo "agents-md-improver content checks passed"
