#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/setup.sh"

fail() {
  echo "codexbar-quota-handoff install-providers check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# A stub `codexbar` on PATH: `guard` reports every provider reachable, and
# nothing else is ever called (claude/grok/codex are only detected via
# `command -v`, never actually invoked, so plain no-op stubs are enough).
STUB_BIN="$TMP_DIR/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/codexbar" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "guard" ]; then
  echo '{"decision":"ok","unavailableReason":null}'
  exit 0
fi
exit 1
STUB
chmod +x "$STUB_BIN/codexbar"

# jq must still resolve; carry the real one onto the stub PATH by symlink.
REAL_JQ="$(command -v jq)" || fail "jq is required to run this test"
ln -s "$REAL_JQ" "$STUB_BIN/jq"

TOOL_BIN="$TMP_DIR/tool-bin"
mkdir -p "$TOOL_BIN"
for tool in claude grok codex; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TOOL_BIN/$tool"
  chmod +x "$TOOL_BIN/$tool"
done

# Runs setup.sh with only the named stub tools (plus codexbar/jq) on PATH.
# Pass no tool names to simulate none of claude/grok/codex being installed.
# Extra args after the tool list are forwarded to setup.sh (e.g. --local).
run_install() {
  local fake_home="$1"
  shift
  mkdir -p "$fake_home/.codexbar"
  echo '{"hooks":{"enabled":false,"events":[]}}' >"$fake_home/.codexbar/config.json"

  local tools=()
  local setup_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        setup_args+=("$@")
        break
        ;;
      *)
        tools+=("$1")
        shift
        ;;
    esac
  done

  local tool_dir="$TMP_DIR/tools-$$-$RANDOM"
  mkdir -p "$tool_dir"
  for tool in "${tools[@]+"${tools[@]}"}"; do
    ln -s "$TOOL_BIN/$tool" "$tool_dir/$tool"
  done

  PATH="$tool_dir:$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$fake_home" \
    XDG_DATA_HOME="$fake_home/xdg-data" \
    XDG_STATE_HOME="$fake_home/xdg-state" \
    bash "$SCRIPT" "${setup_args[@]+"${setup_args[@]}"}"
}

configured_providers() {
  local fake_home="$1"
  "$STUB_BIN/jq" -r '.hooks.events[]?.provider' "$fake_home/.codexbar/config.json" 2>/dev/null | sort | paste -sd, -
}

# --- only claude on PATH: only claude gets a CodexBar rule ---
CLAUDE_ONLY_HOME="$TMP_DIR/claude-only"
mkdir -p "$CLAUDE_ONLY_HOME"
OUTPUT="$(run_install "$CLAUDE_ONLY_HOME" claude)"
ACTUAL="$(configured_providers "$CLAUDE_ONLY_HOME")"
[ "$ACTUAL" = "claude" ] || fail "with only claude on PATH, expected only 'claude' configured, got: $ACTUAL"
case "$OUTPUT" in
  *'claude plugin marketplace add "akunzai/agent-skills"'*'codex plugin marketplace add "akunzai/agent-skills"'*) ;;
  *) fail "setup did not print Claude Code and Codex marketplace commands for akunzai/agent-skills (got: $OUTPUT)" ;;
esac
case "$OUTPUT" in
  *'grok plugin '*)
    fail "setup must not print grok plugin marketplace commands (Grok uses the global hook only)"
    ;;
esac

# --local prints this checkout's absolute path for unpublished testing.
LOCAL_HOME="$TMP_DIR/local-marketplace"
OUTPUT="$(run_install "$LOCAL_HOME" claude --local)"
case "$OUTPUT" in
  *'claude plugin marketplace add "'"$ROOT_DIR"'"'*'codex plugin marketplace add "'"$ROOT_DIR"'"'*) ;;
  *) fail "--local did not print marketplace commands for this checkout (got: $OUTPUT)" ;;
esac
case "$OUTPUT" in
  *'claude plugin marketplace add "akunzai/agent-skills"'*)
    fail "--local must not print the default remote marketplace source"
    ;;
esac

# --- all three tools on PATH: all three providers get a CodexBar rule ---
ALL_TOOLS_HOME="$TMP_DIR/all-tools"
run_install "$ALL_TOOLS_HOME" claude grok codex >/dev/null
ACTUAL="$(configured_providers "$ALL_TOOLS_HOME")"
[ "$ACTUAL" = "claude,codex,grok" ] || fail "with all three tools on PATH, expected all three providers configured, got: $ACTUAL"

RUNTIME_DIR="$ALL_TOOLS_HOME/xdg-data/codexbar-quota-handoff/scripts"
helper="codexbar-quota-flag.sh"
[ -x "$RUNTIME_DIR/$helper" ] || fail "expected executable installed helper: $helper"
cmp "$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/$helper" "$RUNTIME_DIR/$helper" \
  || fail "installed helper differs from repository source: $helper"
EXPECTED_STATE_DIR="$ALL_TOOLS_HOME/xdg-state/codexbar-quota-handoff"
# shellcheck disable=SC2016
"$STUB_BIN/jq" -e --arg exe "$RUNTIME_DIR/codexbar-quota-flag.sh" --arg state "$EXPECTED_STATE_DIR" '
  all(.hooks.events[]; .executable == $exe and .arguments == [.provider, $state])
' "$ALL_TOOLS_HOME/.codexbar/config.json" >/dev/null \
  || fail "CodexBar rules do not use the installed helper and explicit state directory"
[ ! -e "$ALL_TOOLS_HOME/.claude/skills/codexbar-quota-handoff" ] \
  || fail "setup must not install the legacy Claude skill symlink"

# --- Grok on PATH: setup owns ~/.grok/hooks/codexbar-quota-handoff.json and ~/.grok/hooks/codexbar-quota-reminder.sh ---
# Grok 1.0.x discovers plugin hooks but does not register them on the session
# dispatcher, so the reliable path is a global hook alongside its reminder script
# in ~/.grok/hooks/. Stop only: PostToolUse exit 2 is fail-open on Grok and would
# claim the flag before Stop can surface the reminder.
GROK_HOOK_HOME="$TMP_DIR/grok-hook"
run_install "$GROK_HOOK_HOME" grok >/dev/null
GROK_HOOK_FILE="$GROK_HOOK_HOME/.grok/hooks/codexbar-quota-handoff.json"
GROK_HOOK_SCRIPT="$GROK_HOOK_HOME/.grok/hooks/codexbar-quota-reminder.sh"
[ -f "$GROK_HOOK_FILE" ] || fail "expected Grok global hook at $GROK_HOOK_FILE"
[ -x "$GROK_HOOK_SCRIPT" ] || fail "expected executable Grok reminder script at $GROK_HOOK_SCRIPT"
cmp "$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/quota-reminder.sh" "$GROK_HOOK_SCRIPT" \
  || fail "installed Grok reminder script differs from repository source"
# shellcheck disable=SC2016
"$STUB_BIN/jq" -e --arg cmd "$GROK_HOOK_SCRIPT" '
  .hooks.Stop[0].hooks[0].type == "command"
  and .hooks.Stop[0].hooks[0].command == $cmd
  and (.hooks | has("PostToolUse") | not)
' "$GROK_HOOK_FILE" >/dev/null \
  || fail "Grok global hook must be Stop-only against the installed reminder helper"

# Re-running setup replaces our owned hook file and script.
run_install "$GROK_HOOK_HOME" grok >/dev/null
# shellcheck disable=SC2016
"$STUB_BIN/jq" -e --arg cmd "$GROK_HOOK_SCRIPT" '
  .hooks.Stop[0].hooks[0].command == $cmd
' "$GROK_HOOK_FILE" >/dev/null \
  || fail "re-running setup did not refresh the owned Grok global hook"
[ -x "$GROK_HOOK_SCRIPT" ] || fail "re-running setup did not refresh the owned Grok reminder script"

# Foreign files in ~/.grok/hooks/ must be left alone.
echo '{"hooks":{"SessionStart":[]}}' >"$GROK_HOOK_HOME/.grok/hooks/herdr.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$GROK_HOOK_HOME/.grok/hooks/herdr-agent-state.sh"
chmod +x "$GROK_HOOK_HOME/.grok/hooks/herdr-agent-state.sh"
run_install "$GROK_HOOK_HOME" grok >/dev/null
ACTUAL="$("$STUB_BIN/jq" -c . "$GROK_HOOK_HOME/.grok/hooks/herdr.json")"
[ "$ACTUAL" = '{"hooks":{"SessionStart":[]}}' ] \
  || fail "setup overwrote an unrelated Grok hook file"
[ -x "$GROK_HOOK_HOME/.grok/hooks/herdr-agent-state.sh" ] \
  || fail "setup removed an unrelated Grok script file"

# No grok on PATH: do not create the global hook files.
NO_GROK_HOME="$TMP_DIR/no-grok"
run_install "$NO_GROK_HOME" claude >/dev/null
[ ! -e "$NO_GROK_HOME/.grok/hooks/codexbar-quota-handoff.json" ] \
  || fail "setup wrote a Grok global hook when grok was not on PATH"
[ ! -e "$NO_GROK_HOME/.grok/hooks/codexbar-quota-reminder.sh" ] \
  || fail "setup wrote a Grok reminder script when grok was not on PATH"

# --- none of the three tools on PATH: CodexBar's config is left untouched
#     (no backup file, no rules merged in) ---
NO_TOOLS_HOME="$TMP_DIR/no-tools"
mkdir -p "$NO_TOOLS_HOME"
run_install "$NO_TOOLS_HOME" >/dev/null
ACTUAL="$(configured_providers "$NO_TOOLS_HOME")"
[ -z "$ACTUAL" ] || fail "with no tools on PATH, expected no providers configured, got: $ACTUAL"
BACKUP_COUNT="$(find "$NO_TOOLS_HOME/.codexbar" -name 'config.json.bak.*' | wc -l | tr -d ' ')"
[ "$BACKUP_COUNT" -eq 0 ] || fail "with no tools on PATH, expected no backup file to be created, found $BACKUP_COUNT"
[ -x "$NO_TOOLS_HOME/xdg-data/codexbar-quota-handoff/scripts/codexbar-quota-flag.sh" ] \
  || fail "shared helpers should be installed even when no provider CLI is detected"

# --- a symlinked CodexBar config remains a symlink while its target is updated ---
SYMLINK_HOME="$TMP_DIR/symlink-home"
SYMLINK_TARGET="$TMP_DIR/symlink-config.json"
mkdir -p "$SYMLINK_HOME/.codexbar"
echo '{"hooks":{"enabled":false,"events":[]}}' >"$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_HOME/.codexbar/config.json"
SYMLINK_TOOLS="$TMP_DIR/symlink-tools"
mkdir -p "$SYMLINK_TOOLS"
ln -s "$TOOL_BIN/claude" "$SYMLINK_TOOLS/claude"
PATH="$SYMLINK_TOOLS:$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$SYMLINK_HOME" \
  bash "$SCRIPT" >/dev/null
[ -L "$SYMLINK_HOME/.codexbar/config.json" ] || fail "setup replaced a symlinked CodexBar config"
[ "$(jq -r '.hooks.events[0].provider' "$SYMLINK_TARGET")" = claude ] \
  || fail "setup did not update the symlinked CodexBar config target"

echo "codexbar-quota-handoff install-providers checks passed"
