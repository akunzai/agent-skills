#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-hidden-unicode.sh"

fail() {
  echo "hidden-unicode test failed: $*" >&2
  exit 1
}

if [ ! -x "$SCRIPT" ]; then
  fail "Script $SCRIPT is missing or not executable"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fixtures are planted at runtime into temp git repos, not committed, so the
# hidden characters this test proves detection of never land in this repo's
# own history.

# --- clean repo: visible non-ASCII only, must pass -------------------------
CLEAN_DIR="$TMP_DIR/clean-repo"
mkdir -p "$CLEAN_DIR"
git -C "$CLEAN_DIR" init -q -b main
git -C "$CLEAN_DIR" config user.email "test@example.com"
git -C "$CLEAN_DIR" config user.name "Test User"

# Built from numeric code points (chr()), not literal source bytes, so this
# test file's own encoding can never corrupt what gets planted.
perl -e '
  open(my $fh, ">:encoding(UTF-8)", "$ARGV[0]/clean.txt") or die $!;
  print $fh "em dash " . chr(0x2014) . " arrow " . chr(0x2192)
    . " CJK " . chr(0x6F22) . chr(0x5B57) . " fine\n";
  close $fh;
' "$CLEAN_DIR"
git -C "$CLEAN_DIR" add -A
git -C "$CLEAN_DIR" commit -q -m "clean fixture"

CLEAN_OUT="$TMP_DIR/clean_out"
if ! "$SCRIPT" "$CLEAN_DIR" >"$CLEAN_OUT" 2>&1; then
  fail "clean text with visible non-ASCII (em dash/arrow/CJK) should pass: $(cat "$CLEAN_OUT")"
fi

# --- dirty repo: one planted character per required class ------------------
DIRTY_DIR="$TMP_DIR/dirty-repo"
mkdir -p "$DIRTY_DIR"
git -C "$DIRTY_DIR" init -q -b main
git -C "$DIRTY_DIR" config user.email "test@example.com"
git -C "$DIRTY_DIR" config user.name "Test User"

perl -e '
  my @codepoints = (
    0x200B, 0x200C, 0x200D, 0x200E, 0x200F,   # zero-width / bidi marks
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,   # bidi embedding/override
    0x2060, 0x2061, 0x2062, 0x2063, 0x2064,   # word joiner / invisible math ops
    0x2066, 0x2067, 0x2068, 0x2069,           # bidi isolates
    0xFEFF,                                    # BOM / zero-width no-break space
    0x00AD,                                    # soft hyphen
    0x180E,                                    # Mongolian vowel separator
    0xE0000, 0xE0041, 0xE007F,                # tag characters
  );
  open(my $fh, ">:encoding(UTF-8)", "$ARGV[0]/hidden.txt") or die $!;
  for my $cp (@codepoints) {
    printf $fh "line for %04X: before%safter\n", $cp, chr($cp);
  }
  close $fh;
' "$DIRTY_DIR"
git -C "$DIRTY_DIR" add -A
git -C "$DIRTY_DIR" commit -q -m "hidden-unicode fixture"

set +e
OUTPUT="$("$SCRIPT" "$DIRTY_DIR" 2>&1)"
STATUS=$?
set -e

[ "$STATUS" -ne 0 ] || fail "expected nonzero exit for planted hidden-unicode fixtures, got 0 (script may be stubbed). output: $OUTPUT"

for cp in \
  200B 200C 200D 200E 200F \
  202A 202B 202C 202D 202E \
  2060 2061 2062 2063 2064 \
  2066 2067 2068 2069 \
  FEFF 00AD 180E E0000 E0041 E007F
do
  printf '%s\n' "$OUTPUT" | grep -q "^hidden\.txt:[0-9]\+:U+${cp}$" \
    || fail "missing report for U+${cp} in: $OUTPUT"
done

echo "hidden-unicode tests passed"
