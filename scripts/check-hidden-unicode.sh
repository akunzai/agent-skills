#!/usr/bin/env bash
# Scans tracked text files for hidden/invisible Unicode characters that can
# smuggle instructions past a human reviewer while an agent still executes
# them (OWASP Agentic Skills AST04.2). Fails, printing path:line:codepoint,
# when it finds:
#   - zero-width and bidi-control characters (U+200B-200F, U+202A-202E,
#     U+2060-2064, U+2066-2069)
#   - the byte-order mark / zero-width no-break space (U+FEFF)
#   - soft hyphen (U+00AD) and the deprecated Mongolian vowel separator
#     (U+180E)
#   - Unicode tag characters (U+E0000-E007F)
# Visible non-ASCII text (em dashes, CJK, arrows, ...) is left untouched.
#
# Perl-based rather than relying on a GNU-only grep/sed feature, so this
# runs unchanged under Bash 4+ on Ubuntu and the stock /bin/bash 3.2 on
# macOS -- see docs/agents/harnesses.md and the bash32-compat CI job.
#
# Usage: check-hidden-unicode.sh [DIR]
#   DIR defaults to the current directory and must be inside a Git work tree.
set -euo pipefail

TARGET_DIR="${1:-.}"

cd "$TARGET_DIR"

STATUS=0

is_binary() {
  # Mirrors git's own "contains a NUL byte" heuristic for classifying a
  # file as binary, so images/fonts/archives are skipped instead of
  # producing decode noise or false hits.
  perl -e '
    local $/;
    open(my $fh, "<:raw", $ARGV[0]) or exit 1;
    my $data = <$fh>;
    exit(( defined $data && index($data, "\x00") >= 0 ) ? 0 : 1);
  ' "$1"
}

scan_file() {
  perl -CSD -ne '
    BEGIN { $ok = 1 }
    while (/([\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{00AD}\x{180E}\x{E0000}-\x{E007F}])/g) {
      printf("%s:%d:U+%04X\n", $ARGV, $., ord($1));
      $ok = 0;
    }
    END { exit($ok ? 0 : 1) }
  ' "$1"
}

while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue
  if is_binary "$file"; then
    continue
  fi
  if ! scan_file "$file"; then
    STATUS=1
  fi
done < <(git ls-files -z)

if [ "$STATUS" -ne 0 ]; then
  echo "hidden Unicode characters found (see path:line:codepoint above)" >&2
fi

exit "$STATUS"
