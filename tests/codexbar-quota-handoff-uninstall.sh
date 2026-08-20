#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/uninstall.sh"

fail() {
  echo "codexbar-quota-handoff uninstall check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_HOME="$TMP_DIR/home"
DATA_HOME="$FAKE_HOME/xdg-data"
STATE_HOME="$FAKE_HOME/xdg-state"
RUNTIME_ROOT="$DATA_HOME/codexbar-quota-handoff"
STATE_DIR="$STATE_HOME/codexbar-quota-handoff"
mkdir -p "$FAKE_HOME/.codexbar" "$FAKE_HOME/.grok/hooks" "$RUNTIME_ROOT/scripts" "$STATE_DIR"
touch "$RUNTIME_ROOT/scripts/codexbar-quota-flag.sh" \
  "$STATE_DIR/quota-low-claude.json" \
  "$FAKE_HOME/.grok/hooks/codexbar-quota-reminder.sh"
echo '{"hooks":{"Stop":[]}}' >"$FAKE_HOME/.grok/hooks/codexbar-quota-handoff.json"
echo '{"hooks":{"SessionStart":[]}}' >"$FAKE_HOME/.grok/hooks/herdr.json"

cat >"$FAKE_HOME/.codexbar/config.json" <<'EOF'
{"hooks":{"enabled":true,"events":[
  {"id":"agent-skills-codexbar-quota-handoff-claude","provider":"claude"},
  {"id":"agent-skills-codexbar-quota-handoff-grok","provider":"grok"},
  {"id":"agent-skills-codexbar-quota-handoff-codex","provider":"codex"},
  {"id":"someone-elses-rule","provider":"claude"}
]}}
EOF

OUTPUT="$(HOME="$FAKE_HOME" XDG_DATA_HOME="$DATA_HOME" XDG_STATE_HOME="$STATE_HOME" bash "$SCRIPT")"
[ ! -e "$RUNTIME_ROOT" ] || fail "runtime helper directory was not removed"
[ ! -e "$STATE_DIR" ] || fail "state directory was not removed"
[ ! -e "$FAKE_HOME/.grok/hooks/codexbar-quota-handoff.json" ] \
  || fail "owned Grok global hook was not removed"
[ ! -e "$FAKE_HOME/.grok/hooks/codexbar-quota-reminder.sh" ] \
  || fail "owned Grok reminder script was not removed"
[ -f "$FAKE_HOME/.grok/hooks/herdr.json" ] \
  || fail "uninstall removed an unrelated Grok hook file"
REMAINING_IDS="$(jq -r '.hooks.events[].id' "$FAKE_HOME/.codexbar/config.json")"
[ "$REMAINING_IDS" = "someone-elses-rule" ] || fail "unrelated CodexBar rule did not survive"
case "$OUTPUT" in
  *'claude plugin uninstall '*'codex plugin remove '*) ;;
  *) fail "uninstall did not print Claude Code and Codex plugin-manager commands" ;;
esac
case "$OUTPUT" in
  *'grok plugin '*)
    fail "uninstall must not print grok plugin commands (Grok uses the global hook only)"
    ;;
esac

# --keep-state preserves state while removing every host integration.
KEEP_HOME="$TMP_DIR/keep-home"
KEEP_DATA="$KEEP_HOME/data"
KEEP_STATE="$KEEP_HOME/state/codexbar-quota-handoff"
mkdir -p "$KEEP_DATA/codexbar-quota-handoff/scripts" "$KEEP_STATE"
touch "$KEEP_DATA/codexbar-quota-handoff/scripts/codexbar-quota-flag.sh" "$KEEP_STATE/quota-low-grok.json"
HOME="$KEEP_HOME" XDG_DATA_HOME="$KEEP_DATA" XDG_STATE_HOME="$KEEP_HOME/state" \
  bash "$SCRIPT" --keep-state >/dev/null
[ -f "$KEEP_STATE/quota-low-grok.json" ] || fail "--keep-state removed quota state"
[ ! -e "$KEEP_DATA/codexbar-quota-handoff" ] || fail "--keep-state preserved runtime helpers"

# A symlinked CodexBar config keeps its link while the target is cleaned.
SYMLINK_HOME="$TMP_DIR/symlink-home"
SYMLINK_TARGET="$TMP_DIR/symlink-config.json"
mkdir -p "$SYMLINK_HOME/.codexbar"
echo '{"hooks":{"events":[{"id":"agent-skills-codexbar-quota-handoff-claude"}]}}' >"$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_HOME/.codexbar/config.json"
HOME="$SYMLINK_HOME" bash "$SCRIPT" --keep-state >/dev/null
[ -L "$SYMLINK_HOME/.codexbar/config.json" ] || fail "uninstall replaced a symlinked CodexBar config"
[ "$(jq '.hooks.events | length' "$SYMLINK_TARGET")" -eq 0 ] \
  || fail "uninstall did not update the symlinked CodexBar config target"

# Help is side-effect free and relative XDG paths are rejected.
HELP_HOME="$TMP_DIR/help-home"
HOME="$HELP_HOME" bash "$SCRIPT" --help >/dev/null
[ ! -e "$HELP_HOME" ] || fail "--help created files"
if HOME="$TMP_DIR/bad-home" XDG_DATA_HOME=relative bash "$SCRIPT" >/dev/null 2>&1; then
  fail "relative XDG_DATA_HOME should fail"
fi

echo "codexbar-quota-handoff uninstall checks passed"
