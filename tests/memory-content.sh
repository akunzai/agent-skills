#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/mem-auto"
CLEAN_DIR="$ROOT_DIR/skills/mem-clean"
PROMOTE_DIR="$ROOT_DIR/skills/mem-promote"

fail() {
  echo "memory content check failed: $*" >&2
  exit 1
}

grep -R -q -E 'handoff delta|fresh agent would need to continue' "$SKILL_DIR" \
  || fail "short-term handoff delta capture guidance is missing"

grep -q -E 'Long-term memory:.*durable' "$SKILL_DIR/SKILL.md" \
  || fail "long-term directory structure guidance is missing"
grep -q -E 'Short-term memory:.*\[Candidate\]' "$SKILL_DIR/SKILL.md" \
  || fail "short-term directory structure guidance is missing"

grep -R -q -E 'Reference existing artifacts by path or URL|safe artifact paths or URLs' "$SKILL_DIR" \
  || fail "artifact reference guidance is missing"

grep -R -q -E 'suggested skills' "$SKILL_DIR" \
  || fail "suggested skills handoff guidance is missing"

grep -R -q -E 'Redact Handoffs|redact secrets' "$SKILL_DIR" \
  || fail "short-term redaction guidance is missing"

grep -R -q -E 'Not Handoff-Only|handoff notes as source material' "$PROMOTE_DIR" \
  || fail "handoff-only promotion exclusion is missing"

grep -R -q -E 'transient active state|active handoff.*must not be promoted' "$SKILL_DIR" \
  || fail "active handoff transient-state boundary is missing"

grep -R -q -E '\[Handoff:done\]|appending .Handoff:done' "$SKILL_DIR" \
  || fail "handoff closure-by-append (not delete) rule is missing"

grep -R -q -E 'Default retention is .?30 days|Retention: 30 days' "$CLEAN_DIR" \
  || fail "short-term cleanup default retention is missing"

grep -R -q -E 'Ask the user to confirm|explicit confirmation before execution|require explicit confirmation|require[s]? explicit confirmation' "$CLEAN_DIR" \
  || fail "short-term cleanup confirmation requirement is missing"

grep -R -q -E 'single commit.*memories/<email-localpart>|memories/<email-localpart>.*single commit|rebuild the user.{0,40}single commit' "$CLEAN_DIR" \
  || fail "per-user single-commit compact guidance is missing"

grep -R -q -E 'Delete expired eligible|delete expired global logs|~/.agents/memories' "$CLEAN_DIR" \
  || fail "global short-term cleanup direct deletion guidance is missing"

grep -R -q -E '\[Rejected\].*\[Expired\]|Candidate Resolution Markers' "$CLEAN_DIR" \
  || fail "candidate resolution markers ([Rejected]/[Expired]) guidance is missing"

echo "memory content checks passed"
