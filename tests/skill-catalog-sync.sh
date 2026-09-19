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

# --- catalog manifest: name kebab-cases to "Charley Skills" in skills-manager / `npx skills add` ---
PLUGIN_JSON="$ROOT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"

[ -f "$PLUGIN_JSON" ] || fail ".claude-plugin/plugin.json is missing"
jq empty "$PLUGIN_JSON" 2>/dev/null || fail ".claude-plugin/plugin.json is not valid JSON"

if jq -e 'has("version")' "$PLUGIN_JSON" >/dev/null; then
  fail ".claude-plugin/plugin.json must not have version (catalog only, not a plugin)"
fi

PLUGIN_NAME="$(jq -r '.name // empty' "$PLUGIN_JSON")"
[ "$PLUGIN_NAME" = "charley-skills" ] \
  || fail ".claude-plugin/plugin.json name is '$PLUGIN_NAME', expected 'charley-skills'"

PLUGIN_SKILLS="$(jq -r '.skills // [] | sort | join(",")' "$PLUGIN_JSON")"
EXPECTED_PLUGIN_SKILLS="$(printf '%s\n' "$ON_DISK_SKILLS" | sed 's|^|./skills/|' | paste -sd, -)"
[ "$PLUGIN_SKILLS" = "$EXPECTED_PLUGIN_SKILLS" ] \
  || fail ".claude-plugin/plugin.json skills ($PLUGIN_SKILLS) do not match skills/* ($EXPECTED_PLUGIN_SKILLS)"

[ -f "$MARKETPLACE_JSON" ] || fail ".claude-plugin/marketplace.json is missing"
jq empty "$MARKETPLACE_JSON" 2>/dev/null || fail ".claude-plugin/marketplace.json is not valid JSON"

[ -f "$CODEX_MARKETPLACE_JSON" ] || fail ".agents/plugins/marketplace.json is missing"
jq empty "$CODEX_MARKETPLACE_JSON" 2>/dev/null || fail ".agents/plugins/marketplace.json is not valid JSON"

if jq -e '.plugins[] | select(.name == "charley-skills")' "$MARKETPLACE_JSON" >/dev/null; then
  fail "Claude marketplace must not list charley-skills (catalog skills are not plugins)"
fi
if jq -e '.plugins[] | select(.name == "charley-skills")' "$CODEX_MARKETPLACE_JSON" >/dev/null; then
  fail "Codex marketplace must not list charley-skills (catalog skills are not plugins)"
fi

while IFS= read -r source; do
  [ -n "$source" ] || continue
  case "$source" in
    ./plugins/*) ;;
    *) fail "Claude marketplace source '$source' must be under ./plugins/" ;;
  esac
done < <(jq -r '.plugins[].source' "$MARKETPLACE_JSON")

while IFS= read -r source; do
  [ -n "$source" ] || continue
  case "$source" in
    ./plugins/*) ;;
    *) fail "Codex marketplace path '$source' must be under ./plugins/" ;;
  esac
done < <(jq -r '.plugins[].source.path // empty' "$CODEX_MARKETPLACE_JSON")

echo "skill-catalog-sync checks passed"
