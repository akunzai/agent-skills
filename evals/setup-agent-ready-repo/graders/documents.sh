#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARANTEES="$REPO_DIR/skills/setup-agent-ready-repo/references/guarantees.tsv"

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"

# Every assertion runs, then the grader exits once. Stopping at the first
# failure reported one arbitrary symptom per run and made a single defect look
# like several unrelated flaky ones.
failures=0

fail() {
  echo "$*" >&2
  failures=$((failures + 1))
}

# Markdown hard-wraps prose and indents continuation lines, so a guarantee
# spanning more than a few words straddles a line break and picks up the
# indentation with it. Fold to one line and squeeze the runs, or where the wrap
# happens to fall decides whether a pattern is found.
fold_prose() {
  tr '\n' ' ' | tr -s '[:space:]' ' '
}

require() {
  # require <file> <extended-regex> <message>
  local folded
  folded="$(fold_prose < "$1" 2>/dev/null || true)"
  printf '%s' "$folded" | grep -qiE "$2" || fail "$3"
}

pr="docs/agents/pull-request.md"
issues="docs/agents/issue-tracker.md"
verification="docs/agents/verification.md"

missing=0
for f in "$pr" "$issues" "$verification"; do
  if [ ! -f "$f" ]; then
    fail "$f is missing"
    missing=1
  fi
done
# The remaining assertions all read those files; without them every one would
# fire and bury the single real finding.
[ "$missing" -eq 0 ] || exit 1

# --- the documents are English throughout ---
# The skill's Phase 1 rule: the language answer governs what an agent later
# types into the forge, never the language of the file recording that rule.
# Asserting it directly beats inferring it from whether some English word
# happens to survive further down the file.
# Matches the UTF-8 byte range for CJK ideographs; the language's own name is
# the one literal the skill lets through.
cjk=$'[\xe4-\xe9][\x80-\xbf][\x80-\xbf]'
english_throughout() {
  local f=$1 stray
  stray=$(sed 's/繁體中文//g; s/繁体中文//g' "$f" \
    | LC_ALL=C grep -nE "$cjk" | head -n 1 || true)
  [ -z "$stray" ] \
    || fail "$f is not English throughout (first offending line: ${stray:0:80})"
}
for f in "$pr" "$issues" "$verification"; do
  english_throughout "$f"
done

# --- no unresolved template placeholder reaches the repo ---
# Every template opens with "Replace every <angle placeholder>". A bare
# <language> or an alternation such as <gh | glab> is a template artefact;
# an angle placeholder inside a sample command (`gh issue view <number>`)
# is not, so only those two shapes are caught.
for f in "$pr" "$issues" "$verification"; do
  leftover=$(grep -oE '<language>|<[^<>]+ \| [^<>]+>' "$f" | head -n 1 || true)
  [ -z "$leftover" ] || fail "$f ships an unresolved template placeholder: $leftover"
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

# --- the language answer this task gave, which the list cannot know ---
language='chinese|繁體中文|繁体中文|traditional chinese'
require "$issues" "$language" "$issues does not record the ticket language"
require "$pr" "$language" "$pr does not record the request language"

# --- this task's stack, which the list cannot know either ---
require "$verification" 'docker|compose|stack' \
  "$verification does not mention the stack it could not start"
require "$verification" '<!--[[:space:]]*drift:forge[[:space:]]+github[[:space:]]*-->' \
  "$verification does not record GitHub as the forge"

# --- everything the templates pin for every repo ---
# One source, shared with install-templates.sh --check, so the skill and its
# grader cannot disagree about what a document is supposed to carry.
# A missing list is a broken grader, not a defect in the workspace, so it
# stops here rather than joining the accumulated findings.
if [ ! -f "$GUARANTEES" ]; then
  echo "guarantee list $GUARANTEES is missing" >&2
  exit 1
fi
while IFS=$'\t' read -r doc name pattern origin; do
  case "$doc" in \#*|"") continue ;; esac
  case "$doc" in
    issue-tracker) f="$issues" ;;
    request) f="$pr" ;;
    verification) f="$verification" ;;
    *) fail "guarantee list names an unknown document: $doc"; continue ;;
  esac
  require "$f" "$pattern" "$f no longer carries $name (template: $origin)"
done < "$GUARANTEES"

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

[ "$failures" -eq 0 ] || exit 1
