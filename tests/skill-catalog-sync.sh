#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/skills.sh.json"
README="$ROOT_DIR/README.md"

fail() {
  echo "skill-catalog-sync check failed: $*" >&2
  exit 1
}

[ -f "$CATALOG" ] || fail "skills.sh.json is missing"

jq empty "$CATALOG" 2>/dev/null || fail "skills.sh.json is not valid JSON"

# --- schema structural checks ---
NOT_GROUPED="$(jq -r '.notGrouped // empty' "$CATALOG")"
if [ -n "$NOT_GROUPED" ] && [ "$NOT_GROUPED" != "top" ] && [ "$NOT_GROUPED" != "bottom" ]; then
  fail "skills.sh.json 'notGrouped' must be 'top' or 'bottom'"
fi

# --- every grouped skill slug must have a real skills/<slug>/SKILL.md ---
while IFS= read -r slug; do
  [ -f "$ROOT_DIR/skills/$slug/SKILL.md" ] \
    || fail "skills.sh.json references unknown skill '$slug' (skills/$slug/SKILL.md not found)"
done < <(jq -r '.groupings[].skills[]' "$CATALOG")

# --- README.md's ## Skills group headings and membership must match skills.sh.json ---
GROUP_COUNT="$(jq '.groupings | length' "$CATALOG")"
[ "$GROUP_COUNT" -gt 0 ] || fail "skills.sh.json must have at least one grouping"

for ((i = 0; i < GROUP_COUNT; i++)); do
  TITLE="$(jq -r ".groupings[$i].title // empty" "$CATALOG")"
  [ -n "$TITLE" ] || fail "skills.sh.json grouping $i is missing 'title'"

  DESC="$(jq -r ".groupings[$i].description // empty" "$CATALOG")"
  [ -n "$DESC" ] || fail "skills.sh.json grouping '$TITLE' is missing 'description'"

  EXPECTED="$(jq -r ".groupings[$i].skills | sort | join(\",\")" "$CATALOG")"

  BLOCK="$(awk -v heading="### $TITLE" '
    $0 == heading { found=1; next }
    found && /^### / { exit }
    found && /^## / { exit }
    found { print }
  ' "$README")"

  [ -n "$BLOCK" ] || fail "README.md is missing a '### $TITLE' group heading under ## Skills"

  # shellcheck disable=SC2016
  ACTUAL="$(printf '%s\n' "$BLOCK" \
    | grep -oE '^#### \[`[a-zA-Z0-9_-]+`\]' \
    | sed -E 's/^#### \[`([a-zA-Z0-9_-]+)`\]/\1/' \
    | sort | paste -sd, -)"

  [ "$ACTUAL" = "$EXPECTED" ] \
    || fail "README.md group '$TITLE' skills ($ACTUAL) do not match skills.sh.json ($EXPECTED)"
done

# --- Claude plugin: name kebab-cases to "Charley Skills" in `npx skills add` ---
PLUGIN_JSON="$ROOT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"

[ -f "$PLUGIN_JSON" ] || fail ".claude-plugin/plugin.json is missing"
jq empty "$PLUGIN_JSON" 2>/dev/null || fail ".claude-plugin/plugin.json is not valid JSON"

PLUGIN_NAME="$(jq -r '.name // empty' "$PLUGIN_JSON")"
[ "$PLUGIN_NAME" = "charley-skills" ] \
  || fail ".claude-plugin/plugin.json name is '$PLUGIN_NAME', expected 'charley-skills'"

PLUGIN_SKILLS="$(jq -r '.skills // [] | sort | join(",")' "$PLUGIN_JSON")"
ON_DISK_SKILLS="$(find "$ROOT_DIR/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
  | sort | sed 's|^|./skills/|' | paste -sd, -)"
[ "$PLUGIN_SKILLS" = "$ON_DISK_SKILLS" ] \
  || fail ".claude-plugin/plugin.json skills ($PLUGIN_SKILLS) do not match skills/* ($ON_DISK_SKILLS)"

MARKETPLACE_ENTRY="$(jq -r '.plugins[] | select(.name == "charley-skills") | .source' "$MARKETPLACE_JSON")"
[ "$MARKETPLACE_ENTRY" = "./" ] \
  || fail "Claude marketplace is missing charley-skills with source './' (got: '$MARKETPLACE_ENTRY')"

echo "skill-catalog-sync checks passed"
