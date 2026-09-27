#!/usr/bin/env bash
set -euo pipefail

# Every SKILL.md uses only the portable frontmatter keys CONTRIBUTING.md
# allows, and declares the repository license, so a skill copied out of this
# repo by an installer still carries its terms.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWED="name description license compatibility metadata disable-model-invocation argument-hint"
LICENSE_ID="MIT"

fail() {
  echo "skill-frontmatter test failed: $*" >&2
  exit 1
}

head -1 "$ROOT_DIR/LICENSE" | grep -qx "$LICENSE_ID License" \
  || fail "LICENSE is no longer $LICENSE_ID; update LICENSE_ID and every SKILL.md"

# Print each top-level key of a SKILL.md's frontmatter, one per line.
keys_of() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && /^[A-Za-z_-]+:/ { sub(/:.*/, ""); print }
  ' "$1"
}

# Print the top-level license value, unquoted.
license_of() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && /^license:/ {
      sub(/^license:[[:space:]]*/, "")
      gsub(/["\047]/, "")
      print
      exit
    }
  ' "$1"
}

# Check every SKILL.md under <root>/skills and <root>/plugins/*/skills.
# Prints one line per problem; returns non-zero when any is found.
check_tree() {
  local root="$1" problems=0 file rel key license
  while IFS= read -r file; do
    rel="${file#"$root"/}"
    while IFS= read -r key; do
      if [[ " $ALLOWED " != *" $key "* ]]; then
        echo "$rel: frontmatter key '$key' is not allowed (CONTRIBUTING.md)"
        problems=$((problems + 1))
      fi
    done < <(keys_of "$file")
    license="$(license_of "$file")"
    if [ "$license" != "$LICENSE_ID" ]; then
      echo "$rel: license must be '$LICENSE_ID', got '${license:-<missing>}'"
      problems=$((problems + 1))
    fi
  done < <(find "$root/skills" "$root"/plugins/*/skills -name SKILL.md -type f 2>/dev/null | sort)
  [ "$problems" -eq 0 ]
}

# --- the checker itself rejects each bad declaration ---
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_skill() {
  mkdir -p "$TMP_DIR/$1/skills/demo"
  printf -- '---\nname: demo\ndescription: Demo.\n%s---\n\n# Demo\n' "$2" \
    > "$TMP_DIR/$1/skills/demo/SKILL.md"
}

expect_reject() {
  local out
  if out="$(check_tree "$TMP_DIR/$1")"; then
    fail "fixture '$1' should be rejected"
  fi
  printf '%s\n' "$out" | grep -qF -- "$2" || fail "fixture '$1' did not report '$2': $out"
}

write_skill ok $'license: MIT\ndisable-model-invocation: true\nargument-hint: "[id]"\ncompatibility: Requires git\nmetadata:\n  capabilities: shell\n  paths: nested keys are not top-level\n'
check_tree "$TMP_DIR/ok" >/dev/null || fail "valid fixture was rejected: $(check_tree "$TMP_DIR/ok")"

write_skill quoted $'license: "MIT"\n'
check_tree "$TMP_DIR/quoted" >/dev/null || fail "quoted license was rejected"

write_skill missing $'metadata:\n  capabilities: shell\n'
expect_reject missing "license must be 'MIT', got '<missing>'"

write_skill other-license $'license: Apache-2.0\n'
expect_reject other-license "license must be 'MIT', got 'Apache-2.0'"

write_skill claude-only $'license: MIT\nallowed-tools: Bash\n'
expect_reject claude-only "frontmatter key 'allowed-tools' is not allowed"

write_skill when-to-use $'license: MIT\nwhen_to_use: Use when asked.\n'
expect_reject when-to-use "frontmatter key 'when_to_use' is not allowed"

mkdir -p "$TMP_DIR/plugin/plugins/p"
write_skill plugin/plugins/p $'license: MIT\nhooks: {}\n'
expect_reject plugin "frontmatter key 'hooks' is not allowed"

# --- the repository itself ---
if ! out="$(check_tree "$ROOT_DIR")"; then
  printf '%s\n' "$out" >&2
  fail "one or more SKILL.md files have disallowed frontmatter or a missing license"
fi

count="$(find "$ROOT_DIR/skills" "$ROOT_DIR"/plugins/*/skills -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$count" -gt 0 ] || fail "no SKILL.md files found"
echo "skill-frontmatter tests passed for $count skill(s)"
