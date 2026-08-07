#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT_DIR/skills/to-memory"

fail() {
  echo "to-memory content check failed: $*" >&2
  exit 1
}

# --- scope + tier decisions ---
# shellcheck disable=SC2088
grep -q -E '~/.agents/AGENTS.md' "$DIR/SKILL.md" \
  || fail "long-term global scope must point at the canonical ~/.agents/AGENTS.md"
grep -qiE 'AGENTS\.md.*fallback.*CLAUDE\.md|fallback.*CLAUDE\.md.*AGENTS\.md is absent' "$DIR/SKILL.md" \
  || fail "long-term project scope must document the AGENTS.md-with-CLAUDE.md-fallback rule"
grep -qiE 'no intermediate staging|no intermediate staging or batch review' "$DIR/SKILL.md" \
  || fail "explicit long-term tier must write directly, without a candidate-staging step"

grep -qE 'YYYY-MM-DD-<slug>\.md' "$DIR/SKILL.md" \
  || fail "short-term storage must document the one-file-per-note YYYY-MM-DD-<slug>.md naming convention"
# shellcheck disable=SC2088
grep -q -E '~/.agents/memories/YYYY-MM-DD' "$DIR/SKILL.md" \
  || fail "global short-term directory guidance is missing"
# shellcheck disable=SC2088
grep -q -E '~/.agents/memories/projects/' "$DIR/SKILL.md" \
  || fail "project short-term directory guidance is missing"
grep -q -E 'proj-memory-path\.sh' "$DIR/SKILL.md" \
  || fail "proj-memory-path.sh path resolution guidance is missing"
grep -q -e '--ensure' "$DIR/SKILL.md" \
  || fail "proj-memory-path.sh --ensure guidance is missing"

# --- no dedicated recall/clean/setup skills ---
grep -qziE 'no[[:space:]]+dedicated recall skill' "$DIR/SKILL.md" \
  || fail "SKILL.md must state that no dedicated recall skill is needed"
grep -qiE 'get explicit confirmation' "$DIR/SKILL.md" \
  || fail "deleting a short-term note must require explicit confirmation"

# --- autonomous capture stays with agents-md ---
grep -qiE 'agents-md' "$DIR/SKILL.md" \
  || fail "SKILL.md must delegate autonomous capture to agents-md's Self-Reflection"
grep -qiE 'Self-Reflection' "$DIR/SKILL.md" \
  || fail "SKILL.md must name the Self-Reflection mechanism it defers to"
grep -qiE 'user-invoked only|never runs an autonomous capture loop' "$DIR/SKILL.md" \
  || fail "SKILL.md must state this skill is user-invoked only"

# --- security reference ---
[ -f "$DIR/references/security.md" ] || fail "references/security.md is missing"
grep -qiE 'Passwords, API keys' "$DIR/references/security.md" \
  || fail "security.md must prohibit credentials"
grep -qiE 'PII' "$DIR/references/security.md" \
  || fail "security.md must prohibit PII"

# --- cross-agent setup reference (no script — manual wiring, path table only) ---
[ -f "$DIR/references/cross-agent-locations.md" ] || fail "references/cross-agent-locations.md is missing"
grep -q -E 'cross-agent-locations\.md' "$DIR/SKILL.md" \
  || fail "SKILL.md must link to references/cross-agent-locations.md"
# shellcheck disable=SC2088
grep -q -E '~/.agents/AGENTS.md' "$DIR/references/cross-agent-locations.md" \
  || fail "cross-agent-locations.md must name the canonical core ~/.agents/AGENTS.md"
for agent in "Claude Code" "Codex" "pi" "Gemini" "OpenCode"; do
  grep -qF "$agent" "$DIR/references/cross-agent-locations.md" \
    || fail "cross-agent-locations.md must list a native path for $agent"
done
[ ! -f "$DIR/scripts/cross-agent-bridge.sh" ] \
  || fail "cross-agent-bridge.sh must not exist; wiring is manual, no automation script"

# --- deleted mem-* skills must not linger ---
for skill in mem-auto mem-clean mem-promote mem-recall mem-setup mem-sync; do
  [ ! -d "$ROOT_DIR/skills/$skill" ] || fail "skills/$skill must be removed, replaced by to-memory"
done

echo "to-memory content checks passed"
