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

grep -q -E 'Long-term memory:.*global durable.*~/.agents/AGENTS.md' "$SKILL_DIR/SKILL.md" \
  || fail "long-term memory must point at the canonical ~/.agents/AGENTS.md"
grep -q -E 'Short-term memory:.*~/.agents/memories/projects/' "$SKILL_DIR/SKILL.md" \
  || fail "short-term directory structure guidance must point to ~/.agents/memories/projects/"

grep -q -E 'related-skills:.*mem-recall.*mem-promote.*mem-clean.*mem-sync' "$SKILL_DIR/SKILL.md" \
  || fail "mem-auto must expose related mem-* skills as metadata, not implicit dependencies"

grep -R -q -E 'resolve-proj-memory-path\.sh' "$SKILL_DIR" \
  || fail "resolve-proj-memory-path.sh path resolution guidance is missing in mem-auto"

grep -R -q -E 'Not Handoff-Only|handoff notes as source material' "$PROMOTE_DIR" \
  || fail "handoff-only promotion exclusion is missing"

grep -q -E 'DEPRECATED' "$ROOT_DIR/skills/mem-sync/SKILL.md" \
  || fail "mem-sync must carry a deprecation notice"

grep -q -E 'short-term memory|short-term logs' "$RECALL_DIR/SKILL.md" \
  || fail "mem-recall must focus on short-term memory logs"

# shellcheck disable=SC2016
grep -q -E 'Do not re-read `AGENTS.md` / `CLAUDE.md`|normally load them as project instructions' "$RECALL_DIR/SKILL.md" \
  || fail "mem-recall must not duplicate auto-loaded project instructions"

grep -R -q -E 'Default retention is .?30 days|Retention: 30 days' "$CLEAN_DIR" \
  || fail "short-term cleanup default retention is missing"

grep -R -q -E 'Ask the user to confirm|explicit confirmation before execution|require explicit confirmation|require[s]? explicit confirmation' "$CLEAN_DIR" \
  || fail "short-term cleanup confirmation requirement is missing"

grep -R -q -E 'Delete expired eligible|delete expired global logs|~/.agents/memories' "$CLEAN_DIR" \
  || fail "global short-term cleanup direct deletion guidance is missing"

grep -R -q -E '\[Rejected\].*\[Expired\]|Candidate Resolution Markers' "$CLEAN_DIR" \
  || fail "candidate resolution markers ([Rejected]/[Expired]) guidance is missing"

echo "memory content checks passed"
