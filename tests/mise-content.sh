#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/mise"
SKILL="$SKILL_DIR/SKILL.md"

fail() {
  echo "mise content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/mise/SKILL.md is missing"

grep -q '^name: mise$' "$SKILL" \
  || fail "frontmatter must use name: mise"

grep -q -E '^description: >-' "$SKILL" \
  || fail "description must be present"

# Description states when to use, not a workflow summary.
grep -q -E 'Use when' "$SKILL" \
  || fail "description should start triggers with 'Use when'"

grep -q --fixed-strings 'https://mise.jdx.dev/' "$SKILL" \
  || fail "official mise reference URL is missing"

# Core opinionated conventions.
grep -q -E 'single source of truth' "$SKILL" \
  || fail "single-source-of-truth convention is missing"

grep -q -E 'Pin (versions )?explicitly|pin exact versions' "$SKILL" \
  || fail "explicit version pinning convention is missing"

grep -q --fixed-strings 'mise run' "$SKILL" \
  || fail "tasks-over-scripts (mise run) convention is missing"

grep -q --fixed-strings 'jdx/mise-action@v4' "$SKILL" \
  || fail "pinned CI action jdx/mise-action@v4 is missing"

# Built-in backends and the ubi deprecation gotcha.
grep -q -E 'ubi:' "$SKILL" \
  || fail "ubi deprecation gotcha is missing"

grep -q --fixed-strings 'github:' "$SKILL" \
  || fail "github built-in backend guidance is missing"

# Scope CI tool install with install_args.
grep -q --fixed-strings 'install_args' "$SKILL" \
  || fail "install_args CI tool-scoping guidance is missing"

# Container conventions.
grep -q --fixed-strings 'mise install --system' "$SKILL" \
  || fail "container system-install convention is missing"

# macOS Gatekeeper quarantine gotcha.
grep -q --fixed-strings 'com.apple.quarantine' "$SKILL" \
  || fail "macOS Gatekeeper quarantine gotcha is missing"

# Untrusted mise.toml first-run gotcha.
grep -q --fixed-strings 'mise trust' "$SKILL" \
  || fail "untrusted mise.toml (mise trust) first-run gotcha is missing"

# Cross-link to the aube skill.
grep -q --fixed-strings '../aube/SKILL.md' "$SKILL" \
  || fail "cross-link to the aube skill is missing"

echo "mise content checks passed"
