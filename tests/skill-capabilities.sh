#!/usr/bin/env bash
set -euo pipefail

# Every SKILL.md declares metadata.capabilities from the vocabulary table in
# SECURITY.md (between the capabilities:start/end markers), so a reviewer sees
# what a skill can do before installing it on any runtime.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECURITY_MD="$ROOT_DIR/SECURITY.md"

fail() {
  echo "skill-capabilities test failed: $*" >&2
  exit 1
}

[ -f "$SECURITY_MD" ] || fail "SECURITY.md is missing"

# First backtick term of each table row between the markers.
# shellcheck disable=SC2016
VOCAB="$(awk '
  /<!-- capabilities:start -->/ { on = 1; next }
  /<!-- capabilities:end -->/ { on = 0 }
  on && /^\| `[a-z-]+` \|/ { split($0, a, "`"); print a[2] }
' "$SECURITY_MD")"
[ -n "$VOCAB" ] || fail "no capability vocabulary found between the markers in SECURITY.md"
printf '%s\n' "$VOCAB" | grep -qx none || fail "vocabulary in SECURITY.md lacks 'none'"

# Print metadata.capabilities from a SKILL.md's frontmatter, or nothing.
capabilities_of() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && /^metadata:[[:space:]]*$/ { meta = 1; next }
    fm && meta && /^[^[:space:]]/ { meta = 0 }
    fm && meta && /^[[:space:]]+capabilities:/ {
      sub(/^[[:space:]]+capabilities:[[:space:]]*/, "")
      gsub(/["\047]/, "")
      print
      exit
    }
  ' "$1"
}

# Check every SKILL.md under <root>/skills and <root>/plugins/*/skills.
# Prints one line per problem; returns non-zero when any is found.
check_tree() {
  local root="$1" problems=0 file rel value term count seen
  while IFS= read -r file; do
    rel="${file#"$root"/}"
    value="$(capabilities_of "$file")"
    if [ -z "$value" ]; then
      echo "$rel: missing metadata.capabilities"
      problems=$((problems + 1))
      continue
    fi
    count=0
    seen=","
    while IFS= read -r term; do
      count=$((count + 1))
      if [ -z "$term" ]; then
        echo "$rel: empty capability in '$value'"
        problems=$((problems + 1))
      elif ! printf '%s\n' "$VOCAB" | grep -qxF -- "$term"; then
        echo "$rel: unknown capability '$term' (vocabulary: SECURITY.md)"
        problems=$((problems + 1))
      elif [[ "$seen" == *",$term,"* ]]; then
        echo "$rel: duplicate capability '$term'"
        problems=$((problems + 1))
      fi
      seen="$seen$term,"
    done < <(printf '%s\n' "$value" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [[ "$seen" == *",none,"* ]] && [ "$count" -gt 1 ]; then
      echo "$rel: 'none' must stand alone, got '$value'"
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

write_skill ok $'metadata:\n  replaces: old\n  capabilities: shell, network\n'
check_tree "$TMP_DIR/ok" >/dev/null || fail "valid fixture was rejected: $(check_tree "$TMP_DIR/ok")"

write_skill none-ok $'metadata:\n  capabilities: none\n'
check_tree "$TMP_DIR/none-ok" >/dev/null || fail "'none' alone was rejected"

write_skill missing $'metadata:\n  replaces: old\n'
expect_reject missing "missing metadata.capabilities"

write_skill top-level $'capabilities: shell\n'
expect_reject top-level "missing metadata.capabilities"

write_skill unknown $'metadata:\n  capabilities: shell, sudo\n'
expect_reject unknown "unknown capability 'sudo'"

write_skill none-mixed $'metadata:\n  capabilities: none, shell\n'
expect_reject none-mixed "'none' must stand alone"

write_skill duplicate $'metadata:\n  capabilities: shell, shell\n'
expect_reject duplicate "duplicate capability 'shell'"

write_skill empty-term $'metadata:\n  capabilities: shell,,network\n'
expect_reject empty-term "empty capability"

mkdir -p "$TMP_DIR/plugin/plugins/p"
write_skill plugin/plugins/p $'metadata:\n  capabilities: nope\n'
expect_reject plugin "unknown capability 'nope'"

# --- the repository itself ---
if ! out="$(check_tree "$ROOT_DIR")"; then
  printf '%s\n' "$out" >&2
  fail "one or more SKILL.md files have missing or invalid capabilities"
fi

count="$(find "$ROOT_DIR/skills" "$ROOT_DIR"/plugins/*/skills -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$count" -gt 0 ] || fail "no SKILL.md files found"
echo "skill-capabilities tests passed for $count skill(s)"
