#!/usr/bin/env bash
set -euo pipefail

# Copies this skill's document templates into a target repository, and checks
# installed documents for the two defects an instruction cannot prevent: prose
# that is not English, and an unresolved <angle placeholder>.
#
# Copying is the point. A model asked to write a document from a template
# regenerates it, and regeneration follows the conversation's language, which
# is how a Chinese `# 提交請求` reached a generated pull-request.md. Copying the
# bytes and editing the placeholders in place has no such pull.

usage() {
  cat >&2 <<'USAGE'
usage: install-templates.sh --forge <github|gitlab|none> [--force] [DIR]
       install-templates.sh --check [DIR]

  --forge   which ticket document to install beside verification.md:
            github writes pull-request.md, gitlab writes merge-request.md,
            none writes verification.md alone (no remote)
  --force   overwrite a destination that already exists
  --check   scan installed documents for stray CJK and unresolved placeholders
  DIR       repository root (default: current directory)
USAGE
}

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$SKILL_DIR/references/templates"

FORGE=""
MODE="install"
FORCE=false
DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --forge)
      [ $# -ge 2 ] || { echo "--forge needs a value" >&2; usage; exit 2; }
      FORGE="$2"
      shift
      ;;
    --check) MODE="check" ;;
    --force) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [ -n "$DIR" ]; then
        echo "unexpected argument: $1" >&2
        usage
        exit 2
      fi
      DIR="$1"
      ;;
  esac
  shift
done

DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 2; }
DIR="$(cd "$DIR" && pwd)"
DEST="$DIR/docs/agents"

# Matches the UTF-8 byte range for CJK ideographs, the same test the eval
# grader applies, so the skill and its grader cannot disagree.
CJK=$'[\xe4-\xe9][\x80-\xbf][\x80-\xbf]'

check_docs() {
  local found=0 f stray leftover
  for f in "$DEST/issue-tracker.md" "$DEST/pull-request.md" \
           "$DEST/merge-request.md" "$DEST/verification.md"; do
    [ -f "$f" ] || continue
    stray=$(LC_ALL=C grep -nE "$CJK" "$f" | head -n 1 || true)
    if [ -n "$stray" ]; then
      printf 'NOT ENGLISH %s (first offending line: %s)\n' "${f#"$DIR"/}" "${stray:0:80}"
      found=1
    fi
    # A placeholder inside a sample command (`gh issue view <number>`) is not a
    # template artefact; a bare <language> or an alternation such as
    # <gh | glab> is.
    leftover=$(grep -oE '<language>|<[^<>]+ \| [^<>]+>' "$f" | head -n 1 || true)
    if [ -n "$leftover" ]; then
      printf 'PLACEHOLDER %s still carries %s\n' "${f#"$DIR"/}" "$leftover"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "documents are English and carry no unresolved placeholder"
  fi
  return "$found"
}

install_one() {
  local src="$1" dst="$2"
  [ -f "$src" ] || { echo "missing template: $src" >&2; exit 2; }
  if [ -e "$dst" ] && [ "$FORCE" != true ]; then
    printf 'skip  %s already exists\n' "${dst#"$DIR"/}"
    return 0
  fi
  cp "$src" "$dst"
  printf 'copy  %s\n' "${dst#"$DIR"/}"
}

if [ "$MODE" = check ]; then
  check_docs
  exit $?
fi

case "$FORGE" in
  github|gitlab|none) ;;
  "") echo "--forge is required to install" >&2; usage; exit 2 ;;
  *) echo "unknown forge: $FORGE" >&2; usage; exit 2 ;;
esac

mkdir -p "$DEST"
install_one "$TEMPLATES/verification.md" "$DEST/verification.md"
case "$FORGE" in
  github)
    install_one "$TEMPLATES/issue-tracker.md" "$DEST/issue-tracker.md"
    install_one "$TEMPLATES/pull-request.md" "$DEST/pull-request.md"
    ;;
  gitlab)
    install_one "$TEMPLATES/issue-tracker.md" "$DEST/issue-tracker.md"
    install_one "$TEMPLATES/pull-request.md" "$DEST/merge-request.md"
    ;;
esac

echo "Now edit the copies in place: replace every <angle placeholder>, delete"
echo "the lines that do not apply, and leave the English prose alone."
