#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/codexbar-quota-handoff"
CLAUDE_PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
ANTIGRAVITY_PLUGIN_JSON="$PLUGIN_DIR/plugin.json"
ANTIGRAVITY_HOOKS_JSON="$PLUGIN_DIR/hooks.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
CLAUDE_MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"

fail() {
  echo "codexbar-quota-handoff manifest check failed: $*" >&2
  exit 1
}

for f in "$CLAUDE_PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$ANTIGRAVITY_PLUGIN_JSON" \
  "$ANTIGRAVITY_HOOKS_JSON" "$HOOKS_JSON" \
  "$CLAUDE_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON"; do
  [ -f "$f" ] || fail "$f is missing"
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
done

[ ! -e "$ROOT_DIR/.grok-plugin" ] \
  || fail ".grok-plugin must not exist; Grok Build is not a supported plugin runtime"

CLAUDE_NAME="$(jq -r '.name' "$CLAUDE_PLUGIN_JSON")"
[ "$CLAUDE_NAME" = "codexbar-quota-handoff" ] || fail ".claude-plugin/plugin.json name is '$CLAUDE_NAME', expected 'codexbar-quota-handoff'"

CODEX_NAME="$(jq -r '.name' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_NAME" = "codexbar-quota-handoff" ] || fail ".codex-plugin/plugin.json name is '$CODEX_NAME', expected 'codexbar-quota-handoff'"

AGY_NAME="$(jq -r '.name' "$ANTIGRAVITY_PLUGIN_JSON")"
[ "$AGY_NAME" = "codexbar-quota-handoff" ] || fail "plugin.json name is '$AGY_NAME', expected 'codexbar-quota-handoff'"

CLAUDE_VER="$(jq -r '.version' "$CLAUDE_PLUGIN_JSON")"
CODEX_VER="$(jq -r '.version' "$CODEX_PLUGIN_JSON")"
AGY_VER="$(jq -r '.version' "$ANTIGRAVITY_PLUGIN_JSON")"
[ "$CLAUDE_VER" = "$CODEX_VER" ] || fail "Claude version '$CLAUDE_VER' != Codex '$CODEX_VER'"
[ "$AGY_VER" = "$CLAUDE_VER" ] || fail "Antigravity version '$AGY_VER' != Claude '$CLAUDE_VER'"

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

AGY_CMD="$(jq -r "((.\"codexbar-quota-handoff\".PreInvocation[0].command // .hooks.PreInvocation[0].command) // empty)" "$ANTIGRAVITY_HOOKS_JSON")"
case "$AGY_CMD" in
  *quota-reminder.sh*) ;;
  *) fail "Antigravity hooks.json PreInvocation does not reference quota-reminder.sh (got: $AGY_CMD)" ;;
esac

# --- marketplace.json must actually list this plugin, by the same name ---
CLAUDE_MARKETPLACE_ENTRY="$(jq -r '.plugins[] | select(.name == "codexbar-quota-handoff") | .source' "$CLAUDE_MARKETPLACE_JSON")"
[ "$CLAUDE_MARKETPLACE_ENTRY" = "./plugins/codexbar-quota-handoff" ] \
  || fail "Claude marketplace entry is missing"
CODEX_MARKETPLACE_PATH="$(jq -r '.plugins[] | select(.name == "codexbar-quota-handoff") | .source.path' "$CODEX_MARKETPLACE_JSON")"
[ "$CODEX_MARKETPLACE_PATH" = "./plugins/codexbar-quota-handoff" ] \
  || fail "Codex marketplace entry is missing"

for script in codexbar-quota-flag.sh quota-reminder.sh configure-host.sh remove-host.sh remove-grok.sh; do
  path="$PLUGIN_DIR/scripts/$script"
  [ -f "$path" ] || fail "scripts/$script is missing"
  [ -x "$path" ] || fail "scripts/$script is not executable"
done

echo "codexbar-quota-handoff manifest checks passed"
