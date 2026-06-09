#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/agents-md"

fail() {
  echo "agents-md content check failed: $*" >&2
  exit 1
}

if grep -R -n --fixed-strings 'ln -sf AGENTS.md CLAUDE.md' "$SKILL_DIR"; then
  fail "docs must not recommend force-replacing CLAUDE.md with ln -sf"
fi

if grep -R -n -E 'Use TypeScript for all new code|Vanilla CSS|HSL variables|component files under 200 lines' "$SKILL_DIR/references/templates.md"; then
  fail "starter template must not include framework-specific rules without repo evidence"
fi

# shellcheck disable=SC2016
grep -R -q -E 'If `?CLAUDE\.md`? already exists and is not the intended symlink' "$SKILL_DIR" \
  || fail "safe CLAUDE.md migration rule is missing"

# shellcheck disable=SC2016
grep -R -q -E 'Choose the target `?AGENTS\.md`? explicitly' "$SKILL_DIR" \
  || fail "multi-AGENTS target selection rule is missing"

grep -R -q --fixed-strings 'https://agents.md/' "$SKILL_DIR" \
  || fail "official AGENTS.md reference URL is missing"

grep -R -q -E 'plain Markdown|no required fields' "$SKILL_DIR" \
  || fail "official plain Markdown/no required fields guidance is missing"

grep -R -q -E 'closest .*AGENTS\.md|nearest .*AGENTS\.md' "$SKILL_DIR" \
  || fail "closest AGENTS.md precedence guidance is missing"

echo "agents-md content checks passed"
