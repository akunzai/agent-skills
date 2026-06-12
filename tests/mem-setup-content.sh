#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT_DIR/skills/mem-setup"

fail() { echo "mem-setup content check failed: $*" >&2; exit 1; }

grep -qiE 'dry-run|read-only plan|explicit (user )?confirmation' "$DIR/SKILL.md" \
  || fail "mem-setup must require a dry-run plan and confirmation before apply"
grep -qiE 'never write through (a |the )?symlink' "$DIR/SKILL.md" \
  || fail "mem-setup must state the never-write-through-symlink safety rule"
grep -qiE 'idempotent' "$DIR/SKILL.md" \
  || fail "mem-setup must state idempotency"
# shellcheck disable=SC2088
grep -qE '~/.agents/AGENTS.md' "$DIR/SKILL.md" \
  || fail "mem-setup must name the canonical core ~/.agents/AGENTS.md"
grep -qiE 'import|symlink|instructions' "$DIR/SKILL.md" \
  || fail "mem-setup must document the bridge methods"
grep -qiE 'memory-autoload|MEMORY.md|migrat' "$DIR/SKILL.md" \
  || fail "mem-setup must document migration from the retired plugin"

echo "mem-setup content checks passed"
