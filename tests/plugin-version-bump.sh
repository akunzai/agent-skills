#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "plugin-version-bump check failed: $*" >&2
  exit 1
}

# Claude Code uses plugin.json version as the update cache key. An unchanged
# string makes `claude plugin update` a no-op even when git SHA moved.
# https://code.claude.com/docs/en/plugins-reference#version-management
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

base=""
if [ -n "${GITHUB_BASE_REF:-}" ] && git -C "$ROOT_DIR" rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
  base="origin/${GITHUB_BASE_REF}"
elif git -C "$ROOT_DIR" rev-parse --verify origin/main >/dev/null 2>&1; then
  base=origin/main
fi

if [ -n "${GITHUB_ACTIONS:-}" ] && [ -z "$base" ]; then
  fail "CI needs origin/main or origin/\$GITHUB_BASE_REF to enforce version bumps"
fi

shopt -s nullglob
plugin_jsons=("$ROOT_DIR"/plugins/*/.claude-plugin/plugin.json)
[ "${#plugin_jsons[@]}" -gt 0 ] || fail "no plugins/*/.claude-plugin/plugin.json found"

for plugin_json in "${plugin_jsons[@]}"; do
  plugin_dir="$(cd "$(dirname "$plugin_json")/.." && pwd)"
  name="$(basename "$plugin_dir")"
  version="$(jq -r '.version // empty' "$plugin_json")"
  [ -n "$version" ] || fail "$name Claude plugin.json is missing version"
  [[ "$version" =~ $semver_re ]] || fail "$name Claude version '$version' is not X.Y.Z"

  codex_json="$plugin_dir/.codex-plugin/plugin.json"
  if [ -f "$codex_json" ]; then
    codex_version="$(jq -r '.version // empty' "$codex_json")"
    [ "$codex_version" = "$version" ] \
      || fail "$name Codex version '$codex_version' != Claude '$version'"
  fi

  if [ -n "$base" ]; then
    rel="plugins/$name"
    if git -C "$ROOT_DIR" cat-file -e "$base:$rel/.claude-plugin/plugin.json" 2>/dev/null; then
      # Claude/Copilot Worker Roles are executable Markdown, so agents/*.md is a
      # shipped change. Only contributor docs and the generated upgrade helper
      # are excluded; a plugin-root AGENTS.md/CLAUDE.md is not loaded as plugin
      # context, so it ships nothing.
      if [ -n "$(git -C "$ROOT_DIR" diff --name-only "$base" -- "$rel" \
        ':(exclude)*/README.md' ':(exclude)*/AGENTS.md' ':(exclude)*/CLAUDE.md' \
        ':(exclude)*/scripts/upgrade.sh')" ]; then
        old="$(git -C "$ROOT_DIR" show "$base:$rel/.claude-plugin/plugin.json" | jq -r '.version // empty')"
        [ "$version" != "$old" ] \
          || fail "$name shipped files changed vs $base but version stayed '$version' (Claude Code skips plugin update until version changes)"
      fi
    fi
  fi
done

# The root charley-skills plugin ships skills/** directly (no plugins/<name>/
# wrapper), so it needs the same version-bump discipline as the sub-plugins.
root_json="$ROOT_DIR/.claude-plugin/plugin.json"
[ -f "$root_json" ] || fail "no .claude-plugin/plugin.json found for charley-skills"

root_version="$(jq -r '.version // empty' "$root_json")"
[ -n "$root_version" ] || fail "charley-skills plugin.json is missing version"
[[ "$root_version" =~ $semver_re ]] || fail "charley-skills version '$root_version' is not X.Y.Z"

if [ -n "$base" ] && git -C "$ROOT_DIR" cat-file -e "$base:.claude-plugin/plugin.json" 2>/dev/null; then
  if [ -n "$(git -C "$ROOT_DIR" diff --name-only "$base" -- skills)" ]; then
    root_old="$(git -C "$ROOT_DIR" show "$base:.claude-plugin/plugin.json" | jq -r '.version // empty')"
    [ "$root_version" != "$root_old" ] \
      || fail "charley-skills shipped files (skills/) changed vs $base but version stayed '$root_version' (Claude Code skips plugin update until version changes)"
  fi
fi

echo "plugin-version-bump checks passed"
