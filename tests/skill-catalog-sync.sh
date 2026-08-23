#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT_DIR/README.md"

fail() {
  echo "skill-catalog-sync check failed: $*" >&2
  exit 1
}

[ -f "$README" ] || fail "README.md is missing"

# --- every skill on disk must have a SKILL.md and be listed in README.md ---
ON_DISK_SKILLS="$(find "$ROOT_DIR/skills" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/SKILL.md' ';' -exec basename {} \; | sort)"
[ -n "$ON_DISK_SKILLS" ] || fail "no skills found in skills/"

# shellcheck disable=SC2016
README_SKILLS="$(grep -oE '^#### \[`[a-zA-Z0-9_-]+`\]' "$README" | sed -E 's/^#### \[`([a-zA-Z0-9_-]+)`\]/\1/' | sort)"
[ -n "$README_SKILLS" ] || fail "no skills found in README.md"

[ "$ON_DISK_SKILLS" = "$README_SKILLS" ] \
  || fail "README.md skills mismatch:
On disk:
$ON_DISK_SKILLS
In README:
$README_SKILLS"

# --- verify each skill link in README exists ---
while IFS= read -r slug; do
  [ -f "$ROOT_DIR/skills/$slug/SKILL.md" ] \
    || fail "README references skill '$slug' but skills/$slug/SKILL.md not found"
done <<< "$README_SKILLS"

# --- Claude plugin: name kebab-cases to "Charley Skills" in skills-manager / `npx skills add` ---
PLUGIN_JSON="$ROOT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"

[ -f "$PLUGIN_JSON" ] || fail ".claude-plugin/plugin.json is missing"
jq empty "$PLUGIN_JSON" 2>/dev/null || fail ".claude-plugin/plugin.json is not valid JSON"

PLUGIN_NAME="$(jq -r '.name // empty' "$PLUGIN_JSON")"
[ "$PLUGIN_NAME" = "charley-skills" ] \
  || fail ".claude-plugin/plugin.json name is '$PLUGIN_NAME', expected 'charley-skills'"

PLUGIN_SKILLS="$(jq -r '.skills // [] | sort | join(",")' "$PLUGIN_JSON")"
EXPECTED_PLUGIN_SKILLS="$(printf '%s\n' "$ON_DISK_SKILLS" | sed 's|^|./skills/|' | paste -sd, -)"
[ "$PLUGIN_SKILLS" = "$EXPECTED_PLUGIN_SKILLS" ] \
  || fail ".claude-plugin/plugin.json skills ($PLUGIN_SKILLS) do not match skills/* ($EXPECTED_PLUGIN_SKILLS)"

[ -f "$MARKETPLACE_JSON" ] || fail ".claude-plugin/marketplace.json is missing"
jq empty "$MARKETPLACE_JSON" 2>/dev/null || fail ".claude-plugin/marketplace.json is not valid JSON"

MARKETPLACE_ENTRY="$(jq -r '.plugins[] | select(.name == "charley-skills") | .source' "$MARKETPLACE_JSON")"
[ "$MARKETPLACE_ENTRY" = "./" ] \
  || fail "Claude marketplace is missing charley-skills with source './' (got: '$MARKETPLACE_ENTRY')"

echo "skill-catalog-sync checks passed"
