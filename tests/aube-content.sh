#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/aube"
SKILL="$SKILL_DIR/SKILL.md"

fail() {
  echo "aube content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/aube/SKILL.md is missing"

grep -q '^name: aube$' "$SKILL" \
  || fail "frontmatter must use name: aube"

grep -q -E '^description: >-' "$SKILL" \
  || fail "description must be present"

grep -q -E 'Use when' "$SKILL" \
  || fail "description should start triggers with 'Use when'"

grep -q --fixed-strings 'https://aube.jdx.dev/' "$SKILL" \
  || fail "official aube reference URL is missing"

# Install through mise, not standalone.
grep -q --fixed-strings 'mise use aube' "$SKILL" \
  || fail "install-through-mise convention is missing"

# Shorthand command conventions.
grep -q --fixed-strings 'aubr' "$SKILL" \
  || fail "aubr (aube run) shorthand is missing"

grep -q --fixed-strings 'aubx' "$SKILL" \
  || fail "aubx (aube dlx) shorthand is missing"

grep -q --fixed-strings 'aube ci' "$SKILL" \
  || fail "aube ci (frozen lockfile) workflow is missing"

# Single version source: remove packageManager.
grep -q --fixed-strings 'packageManager' "$SKILL" \
  || fail "single-version-source (remove packageManager) convention is missing"

# Lockfile policy: prefer a Dependabot-compatible lockfile over aube-lock.yaml.
grep -q --fixed-strings 'pnpm-lock.yaml' "$SKILL" \
  || fail "Dependabot-compatible lockfile guidance (pnpm-lock.yaml) is missing"

grep -q -E 'Dependabot .*cannot|cannot .*maintain .*aube-lock' "$SKILL" \
  || fail "Dependabot-cannot-maintain-aube-lock rationale is missing"

# Lifecycle-script jail and allowBuilds.
grep -q --fixed-strings 'pnpm.allowBuilds' "$SKILL" \
  || fail "lifecycle-script allowBuilds guidance is missing"

# Gotchas.
grep -q -E 'wrangler-action' "$SKILL" \
  || fail "wrangler-action package-manager detection gotcha is missing"

grep -q --fixed-strings 'aube exec' "$SKILL" \
  || fail "aube exec workaround is missing"

# aube exec swallows global flags unless separated by --.
grep -q --fixed-strings 'aube exec -- tsc --version' "$SKILL" \
  || fail "aube exec global-flag passthrough (--) gotcha is missing"

# CI must cache the aube package store separately from the mise tool binaries.
grep -q --fixed-strings 'aube store path' "$SKILL" \
  || fail "CI aube store cache guidance is missing"

# starship nodejs/package modules loop under aube.
grep -q --fixed-strings 'starship.toml' "$SKILL" \
  || fail "starship nodejs/package loop gotcha is missing"

grep -q -E 'Dependabot' "$SKILL" \
  || fail "Dependabot no-aube-ecosystem gotcha is missing"

# Cross-link to the mise skill.
grep -q --fixed-strings '../mise/SKILL.md' "$SKILL" \
  || fail "cross-link to the mise skill is missing"

echo "aube content checks passed"
