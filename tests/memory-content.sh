#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/mem-auto"
CLEAN_DIR="$ROOT_DIR/skills/mem-clean"
PROMOTE_DIR="$ROOT_DIR/skills/mem-promote"
RECALL_DIR="$ROOT_DIR/skills/mem-recall"

fail() {
  echo "memory content check failed: $*" >&2
  exit 1
}

grep -R -q -E 'handoff delta|fresh agent would need to continue' "$SKILL_DIR" \
  || fail "short-term handoff delta capture guidance is missing"

# shellcheck disable=SC2088
grep -q -E 'Long-term memory:.*global durable.*~/.agents/AGENTS.md' "$SKILL_DIR/SKILL.md" \
  || fail "long-term memory must point at the canonical ~/.agents/AGENTS.md"
grep -q -E 'Short-term memory:.*\[Candidate\]' "$SKILL_DIR/SKILL.md" \
  || fail "short-term directory structure guidance is missing"

grep -q -E 'related-skills:.*mem-recall.*mem-promote.*mem-clean.*mem-sync' "$SKILL_DIR/SKILL.md" \
  || fail "mem-auto must expose related mem-* skills as metadata, not implicit dependencies"

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

grep -R -q -E 'delete that task.?s handoff file|deleted on completion' "$SKILL_DIR" \
  || fail "handoff closure-by-delete rule is missing"

grep -R -q -E '\.memories/handoffs/' "$SKILL_DIR" \
  || fail "per-task handoff files must live under .memories/handoffs/"

grep -R -q -E 'one-time migration|handoff-migration' "$SKILL_DIR" \
  || fail "one-time handoff migration guidance is missing"

grep -R -q -E 'mem-sync-git\.sh status.*diff|status.*diff.*read-only' "$SKILL_DIR" \
  || fail "mem-auto must delegate read-only project memory difference checks to mem-sync status/diff"

# shellcheck disable=SC2016
grep -q -E 'Do not read `.memories/` in parallel|Wait for the sync command to[[:space:]]+finish' "$ROOT_DIR/skills/mem-sync/SKILL.md" \
  || fail "mem-sync must warn against parallel reads during pull/push/compact"

grep -q -E 'short-term memory|short-term logs' "$RECALL_DIR/SKILL.md" \
  || fail "mem-recall must focus on short-term memory logs"

# shellcheck disable=SC2016
grep -q -E 'Do not re-read `AGENTS.md` / `CLAUDE.md`|normally load them as project instructions' "$RECALL_DIR/SKILL.md" \
  || fail "mem-recall must not duplicate auto-loaded project instructions"

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
