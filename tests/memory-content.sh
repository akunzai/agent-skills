#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/memory"

fail() {
  echo "memory content check failed: $*" >&2
  exit 1
}

grep -R -q -E 'handoff delta|fresh agent would need to continue' "$SKILL_DIR" \
  || fail "short-term handoff delta capture guidance is missing"

grep -R -q -E 'Long-term memory:.*durable|Short-term memory:.*handoff/candidate logs' "$SKILL_DIR/SKILL.md" \
  || fail "long-term and short-term directory structure guidance is missing"

grep -R -q -E 'Reference existing artifacts by path or URL|safe artifact paths or URLs' "$SKILL_DIR" \
  || fail "artifact reference guidance is missing"

grep -R -q -E 'suggested skills' "$SKILL_DIR" \
  || fail "suggested skills handoff guidance is missing"

grep -R -q -E 'Redact Handoffs|redact secrets' "$SKILL_DIR" \
  || fail "short-term redaction guidance is missing"

grep -R -q -E 'Not Handoff-Only|handoff notes as source material' "$SKILL_DIR" \
  || fail "handoff-only promotion exclusion is missing"

echo "memory content checks passed"
