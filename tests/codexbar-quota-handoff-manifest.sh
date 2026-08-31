#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/codexbar-quota-handoff"
CLAUDE_PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
CLAUDE_MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"
GROK_MARKETPLACE_JSON="$ROOT_DIR/.grok-plugin/marketplace.json"

fail() {
  echo "codexbar-quota-handoff manifest check failed: $*" >&2
  exit 1
}

for f in "$CLAUDE_PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$HOOKS_JSON" \
  "$CLAUDE_MARKETPLACE_JSON" "$GROK_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON"; do
  [ -f "$f" ] || fail "$f is missing"
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
done

CLAUDE_NAME="$(jq -r '.name' "$CLAUDE_PLUGIN_JSON")"
[ "$CLAUDE_NAME" = "codexbar-quota-handoff" ] || fail ".claude-plugin/plugin.json name is '$CLAUDE_NAME', expected 'codexbar-quota-handoff'"

CODEX_NAME="$(jq -r '.name' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_NAME" = "codexbar-quota-handoff" ] || fail ".codex-plugin/plugin.json name is '$CODEX_NAME', expected 'codexbar-quota-handoff'"

CODEX_HOOKS_PATH="$(jq -r '.hooks' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_HOOKS_PATH" = "./hooks/hooks.json" ] || fail ".codex-plugin/plugin.json hooks field is '$CODEX_HOOKS_PATH', expected './hooks/hooks.json' (shared with .claude-plugin)"

# --- a single hooks/hooks.json must be shared by all four tools (Copilot
#     registers this same Claude-shaped nested form): no
#     per-tool arguments, so it can't drift into referencing a provider or
#     a handoff-command string a shell might reinterpret (e.g. "$handoff").
#     Registered on both Stop (once per turn) and PostToolUse (once per tool
#     call, closing the gap where a long, continuous run of tool calls within
#     one turn could burn through quota before Stop ever fires) ---
for event in Stop PostToolUse; do
  COMMAND="$(jq -r ".hooks.${event}[0].hooks[0].command" "$HOOKS_JSON")"
  case "$COMMAND" in
    *quota-reminder.sh*) ;;
    *) fail "hooks.json $event command does not reference quota-reminder.sh (got: $COMMAND)" ;;
  esac

  # shellcheck disable=SC2016
  case "$COMMAND" in
    *'${CLAUDE_PLUGIN_ROOT}'*) ;;
    *) fail "hooks.json $event command should be rooted at \${CLAUDE_PLUGIN_ROOT} (got: $COMMAND)" ;;
  esac

  HAS_ARGS="$(jq -r ".hooks.${event}[0].hooks[0] | has(\"args\")" "$HOOKS_JSON")"
  [ "$HAS_ARGS" = "false" ] || fail "hooks.json $event command should carry no per-tool args (the script self-detects); found an args field"
done

# --- marketplace.json must actually list this plugin, by the same name ---
for marketplace in "$CLAUDE_MARKETPLACE_JSON" "$GROK_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON"; do
  MARKETPLACE_PLUGIN_NAME="$(jq -r '.plugins[0].name' "$marketplace")"
  [ "$MARKETPLACE_PLUGIN_NAME" = "codexbar-quota-handoff" ] \
    || fail "$marketplace first plugin is '$MARKETPLACE_PLUGIN_NAME', expected 'codexbar-quota-handoff'"
  MARKETPLACE_PLUGIN_PATH="$(jq -r '.plugins[0].source | if type == "object" then .path else . end' "$marketplace")"
  [ "$MARKETPLACE_PLUGIN_PATH" = "./plugins/codexbar-quota-handoff" ] \
    || fail "$marketplace source is '$MARKETPLACE_PLUGIN_PATH', expected './plugins/codexbar-quota-handoff'"
done

for script in codexbar-quota-flag.sh quota-reminder.sh setup.sh uninstall.sh; do
  path="$PLUGIN_DIR/scripts/$script"
  [ -f "$path" ] || fail "scripts/$script is missing"
  [ -x "$path" ] || fail "scripts/$script is not executable"
done

echo "codexbar-quota-handoff manifest checks passed"
