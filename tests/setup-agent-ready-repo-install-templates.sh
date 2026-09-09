#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/setup-agent-ready-repo/scripts/install-templates.sh"

fail() {
  echo "setup-agent-ready-repo-install-templates test failed: $*" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "$SCRIPT is missing or not executable"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- GitHub installs the pull-request document, never the merge-request one ---
GH_DIR="$TMP_DIR/gh"
mkdir -p "$GH_DIR"
"$SCRIPT" --forge github "$GH_DIR" >/dev/null
for f in issue-tracker.md pull-request.md verification.md; do
  [ -f "$GH_DIR/docs/agents/$f" ] || fail "github install did not write $f"
done
[ ! -f "$GH_DIR/docs/agents/merge-request.md" ] \
  || fail "github install wrote merge-request.md"

# The copy is byte-identical to the template: that is the whole point of
# copying rather than regenerating.
cmp -s "$ROOT_DIR/skills/setup-agent-ready-repo/references/templates/pull-request.md" \
       "$GH_DIR/docs/agents/pull-request.md" \
  || fail "installed pull-request.md is not a byte copy of its template"

# --- re-running never clobbers an edited document ---
echo "edited by the agent" >> "$GH_DIR/docs/agents/verification.md"
BEFORE="$(cksum < "$GH_DIR/docs/agents/verification.md")"
"$SCRIPT" --forge github "$GH_DIR" >/dev/null
[ "$BEFORE" = "$(cksum < "$GH_DIR/docs/agents/verification.md")" ] \
  || fail "re-running overwrote an existing document"

# --force is the way to overwrite
"$SCRIPT" --forge github --force "$GH_DIR" >/dev/null
[ "$BEFORE" != "$(cksum < "$GH_DIR/docs/agents/verification.md")" ] \
  || fail "--force did not overwrite"

# --- GitLab names the same template merge-request.md ---
GL_DIR="$TMP_DIR/gl"
mkdir -p "$GL_DIR"
"$SCRIPT" --forge gitlab "$GL_DIR" >/dev/null
[ -f "$GL_DIR/docs/agents/merge-request.md" ] || fail "gitlab install did not write merge-request.md"
[ ! -f "$GL_DIR/docs/agents/pull-request.md" ] || fail "gitlab install wrote pull-request.md"

# --- no remote installs verification.md alone ---
NONE_DIR="$TMP_DIR/none"
mkdir -p "$NONE_DIR"
"$SCRIPT" --forge none "$NONE_DIR" >/dev/null
[ -f "$NONE_DIR/docs/agents/verification.md" ] || fail "none install did not write verification.md"
[ ! -f "$NONE_DIR/docs/agents/issue-tracker.md" ] || fail "none install wrote a ticket document"

# --- check catches an unresolved placeholder in a fresh copy ---
if "$SCRIPT" --check "$GL_DIR" >/dev/null 2>&1; then
  fail "--check passed a freshly copied template that still carries <language>"
fi
# --check exits non-zero when it finds something, so capture before grepping:
# under `set -o pipefail` a pipeline would inherit that exit status.
OUT="$("$SCRIPT" --check "$GL_DIR" 2>&1 || true)"
case "$OUT" in
  *PLACEHOLDER*) ;;
  *) fail "--check did not name the unresolved placeholder: $OUT" ;;
esac

# --- check catches CJK, and passes a resolved English document ---
CJK_DIR="$TMP_DIR/cjk"
mkdir -p "$CJK_DIR/docs/agents"
printf '# Issue tracker\n\nWrite issue bodies in English.\n' > "$CJK_DIR/docs/agents/issue-tracker.md"
# A stub document is behind on guarantees, so the run exits non-zero; what
# this case pins is that its language is not what --check objects to.
OUT="$("$SCRIPT" --check "$CJK_DIR" 2>&1 || true)"
case "$OUT" in
  *"NOT ENGLISH"*) fail "--check called a clean English document not English: $OUT" ;;
esac
printf '# 問題追蹤\n' > "$CJK_DIR/docs/agents/issue-tracker.md"
if "$SCRIPT" --check "$CJK_DIR" >/dev/null 2>&1; then
  fail "--check passed a document written in Chinese"
fi
OUT="$("$SCRIPT" --check "$CJK_DIR" 2>&1 || true)"
case "$OUT" in
  *"NOT ENGLISH"*) ;;
  *) fail "--check did not name the language defect: $OUT" ;;
esac

# --- check reports a guarantee the document has lost, by name and origin ---
BEHIND_DIR="$TMP_DIR/behind"
mkdir -p "$BEHIND_DIR/docs/agents"
# Carries the language rule and nothing else the templates pin.
printf '# Issue tracker: GitHub\n\nWrite issue titles and descriptions in English.\n' \
  > "$BEHIND_DIR/docs/agents/issue-tracker.md"
OUT="$("$SCRIPT" --check "$BEHIND_DIR" 2>&1 || true)"
case "$OUT" in
  *"BEHIND"*) ;;
  *) fail "--check did not report a document behind the templates: $OUT" ;;
esac
case "$OUT" in
  *"the collapsed technical section"*) ;;
  *) fail "--check did not name the missing guarantee: $OUT" ;;
esac
case "$OUT" in
  *"issue-tracker.md, Description shape"*) ;;
  *) fail "--check did not say where in the template to read it: $OUT" ;;
esac
# The one guarantee it does carry is not reported.
case "$OUT" in
  *"the language tickets are written in"*)
    fail "--check reported a guarantee the document carries: $OUT" ;;
esac

# A freshly copied template carries every guarantee, so only the placeholder
# check fires on it.
FRESH_DIR="$TMP_DIR/fresh"
mkdir -p "$FRESH_DIR"
"$SCRIPT" --forge github "$FRESH_DIR" >/dev/null
OUT="$("$SCRIPT" --check "$FRESH_DIR" 2>&1 || true)"
case "$OUT" in
  *"BEHIND"*) fail "a freshly copied template was reported as behind: $OUT" ;;
esac

# --- a guarantee stated across a hard-wrapped, indented line still counts ---
# Markdown wraps prose and indents continuation lines. Matching line by line
# made "personally\n   identifiable" invisible, which reported documents as
# behind on guarantees they plainly carried.
WRAP_DIR="$TMP_DIR/wrap"
mkdir -p "$WRAP_DIR/docs/agents"
cat > "$WRAP_DIR/docs/agents/pull-request.md" <<'DOC'
# Pull requests

Write PR titles, descriptions, and comments in **English**. **Git commit
messages are English**, imperative, subject under 72 characters.

2. Add a visual. Attachments must not contain personally
   identifiable information; use test data, masking, or cropping.
   Use Mermaid `flowchart` for a flow.

Exempt paths: documentation. Open a request as a draft, and never
without the developer asking.
DOC
OUT="$("$SCRIPT" --check "$WRAP_DIR" 2>&1 || true)"
for wrapped in "commit messages staying English" \
  "the rule against personally identifiable information"; do
  case "$OUT" in
    *"$wrapped"*) fail "a wrapped guarantee was reported as missing: $wrapped" ;;
  esac
done

# --- argument handling ---
if "$SCRIPT" --forge bogus "$TMP_DIR" >/dev/null 2>&1; then
  fail "an unknown forge should fail"
fi
if "$SCRIPT" "$TMP_DIR" >/dev/null 2>&1; then
  fail "installing without --forge should fail"
fi
if "$SCRIPT" --bogus "$TMP_DIR" >/dev/null 2>&1; then
  fail "an unknown option should fail"
fi

echo "setup-agent-ready-repo-install-templates tests passed"
