#!/usr/bin/env bash
set -euo pipefail

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"

fail() {
  echo "$*" >&2
  exit 1
}

require() {
  # require <file> <extended-regex> <message>
  grep -qiE "$2" "$1" || fail "$3"
}

pr="docs/agents/pull-request.md"
issues="docs/agents/issue-tracker.md"
verification="docs/agents/verification.md"

for f in "$pr" "$issues" "$verification"; do
  [ -f "$f" ] || fail "$f is missing"
done

# --- GitHub vocabulary, not GitLab ---
if [ -f docs/agents/merge-request.md ]; then
  fail "wrote merge-request.md for a GitHub repo"
fi
require "$pr" 'pull request' "$pr never says pull request"
require "$pr" '(^|[^a-z])gh ' "$pr does not use the gh CLI"
# A passing mention of GitLab's term is fine; leading with it is not.
if head -n 15 "$pr" | grep -qiE 'merge request'; then
  fail "$pr opens with GitLab vocabulary"
fi
if grep -qE '(^|[^a-z])glab ' "$pr"; then
  fail "$pr reaches for glab on a GitHub repo"
fi

# --- the language split survives: tickets Chinese, commits English ---
language='chinese|繁體中文|繁体中文|traditional chinese'
require "$issues" "$language" "$issues does not record the ticket language"
require "$pr" "$language" "$pr does not record the request language"
require "$pr" 'commit[^.]*english|english[^.]*commit' \
  "$pr does not keep commit messages in English"

# --- the body shape is carried, not merely named ---
require "$issues" '<details>' "$issues lacks the collapsed technical section"
require "$issues" 'acceptance criteria|驗收條件' \
  "$issues has no shape for an issue an agent implements from"
require "$pr" 'mermaid|flowchart|sequencediagram|erdiagram' \
  "$pr does not say which diagram to use"
if ! grep -qiE 'personally identifiable|\bPII\b' "$issues" "$pr"; then
  fail "neither document carries the PII rule"
fi

# --- verification is honest about what it could not do ---
require "$pr" 'draft' "$pr does not cover the draft-first order"
require "$pr" 'exempt|excluded' "$pr does not name the paths exempt from tests"

require "$verification" 'not verified|unverified|could not be verified' \
  "$verification has no section for what went unverified"
require "$verification" 'docker|compose|stack' \
  "$verification does not mention the stack it could not start"

# --- drift markers, so check-drift.sh has something to read ---
require "$verification" 'drift:entrypoint' \
  "$verification is missing the drift:entrypoint marker"
require "$verification" '<!--[[:space:]]*drift:forge[[:space:]]+github[[:space:]]*-->' \
  "$verification does not record GitHub as the forge"

# --- AGENTS.md points at all three, and nothing secret was written ---
for doc in issue-tracker pull-request verification; do
  grep -q "@docs/agents/$doc.md" AGENTS.md \
    || fail "AGENTS.md has no @docs/agents/$doc.md pointer"
done

for leak in .env .env.local secrets.md; do
  if [ -e "$leak" ]; then
    fail "wrote $leak"
  fi
done
