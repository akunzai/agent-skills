#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/spoken-tts"
CLAUDE_PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
CLAUDE_MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"

fail() {
  echo "spoken manifest check failed: $*" >&2
  exit 1
}

for f in "$CLAUDE_PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$HOOKS_JSON" \
  "$CLAUDE_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON"; do
  [ -f "$f" ] || fail "$f is missing"
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
done

CLAUDE_NAME="$(jq -r '.name' "$CLAUDE_PLUGIN_JSON")"
[ "$CLAUDE_NAME" = "spoken-tts" ] || fail "Claude plugin name is '$CLAUDE_NAME'"

CODEX_NAME="$(jq -r '.name' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_NAME" = "spoken-tts" ] || fail "Codex plugin name is '$CODEX_NAME'"

CLAUDE_VER="$(jq -r '.version' "$CLAUDE_PLUGIN_JSON")"
CODEX_VER="$(jq -r '.version' "$CODEX_PLUGIN_JSON")"
[ "$CLAUDE_VER" = "$CODEX_VER" ] || fail "Claude version '$CLAUDE_VER' != Codex '$CODEX_VER'"

CODEX_HOOKS_PATH="$(jq -r '.hooks' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_HOOKS_PATH" = "./hooks/hooks.json" ] \
  || fail "Codex hooks field is '$CODEX_HOOKS_PATH'"

for event in Stop UserPromptSubmit; do
  COMMAND="$(jq -r ".hooks.${event}[0].hooks[0].command" "$HOOKS_JSON")"
  case "$COMMAND" in
    *spoken.sh*) ;;
    *) fail "hooks.json $event command does not reference spoken.sh (got: $COMMAND)" ;;
  esac
  # shellcheck disable=SC2016
  case "$COMMAND" in
    *'${CLAUDE_PLUGIN_ROOT}'*) ;;
    *) fail "hooks.json $event is not rooted at \${CLAUDE_PLUGIN_ROOT} (got: $COMMAND)" ;;
  esac
done

STOP_CMD="$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS_JSON")"
case "$STOP_CMD" in
  *hook-stop*) ;;
  *) fail "Stop hook does not call hook-stop (got: $STOP_CMD)" ;;
esac

PROMPT_CMD="$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS_JSON")"
case "$PROMPT_CMD" in
  *hook-prompt*) ;;
  *) fail "UserPromptSubmit hook does not call hook-prompt (got: $PROMPT_CMD)" ;;
esac

if jq -e '.hooks.SubagentStop' "$HOOKS_JSON" >/dev/null 2>&1; then
  fail "SubagentStop must not be registered"
fi

CLAUDE_MARKETPLACE_ENTRY="$(jq -r '.plugins[] | select(.name == "spoken-tts") | .source' "$CLAUDE_MARKETPLACE_JSON")"
[ "$CLAUDE_MARKETPLACE_ENTRY" = "./plugins/spoken-tts" ] \
  || fail "Claude marketplace entry is missing"

CODEX_MARKETPLACE_PATH="$(jq -r '.plugins[] | select(.name == "spoken-tts") | .source.path' "$CODEX_MARKETPLACE_JSON")"
[ "$CODEX_MARKETPLACE_PATH" = "./plugins/spoken-tts" ] \
  || fail "Codex marketplace entry is missing"

grep -q 'plugins/spoken-tts/README.md' "$ROOT_DIR/README.md" \
  || fail "root README is missing the spoken-tts plugin"

[ -f "$PLUGIN_DIR/skills/spoken/SKILL.md" ] || fail "skills/spoken/SKILL.md is missing"
[ -f "$PLUGIN_DIR/skills/spoken/references/line.md" ] \
  || fail "skills/spoken/references/line.md is missing"

path="$PLUGIN_DIR/scripts/spoken.sh"
[ -f "$path" ] || fail "scripts/spoken.sh is missing"
[ -x "$path" ] || fail "scripts/spoken.sh is not executable"

for script in setup.sh upgrade.sh uninstall.sh; do
  [ ! -e "$PLUGIN_DIR/scripts/$script" ] \
    || fail "plugins/spoken-tts/scripts/$script must not be a public lifecycle entry point"
done

echo "spoken manifest checks passed"
