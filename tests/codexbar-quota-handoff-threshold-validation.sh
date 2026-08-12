#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/setup.sh"

fail() {
  echo "codexbar-quota-handoff threshold-validation check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- help must succeed without inspecting or changing the machine ---
for option in -h --help; do
  RC=0
  OUTPUT="$(HOME="$TMP_DIR/help-home" bash "$SCRIPT" "$option" 2>&1)" || RC=$?
  [ "$RC" -eq 0 ] || fail "$option should exit 0, got exit $RC"
  case "$OUTPUT" in
    *"Usage:"*"--threshold"*"--local"*"--help"*) ;;
    *) fail "$option output is missing usage or supported options (got: $OUTPUT)" ;;
  esac
  [ ! -e "$TMP_DIR/help-home" ] || fail "$option should not create files"
done

# --- out-of-range and non-numeric values must be rejected before any tool
#     or CodexBar detection runs, so this is safe to test without any of
#     Claude Code, Grok Build, Codex CLI, or CodexBar present ---
assert_rejected() {
  local value="$1"
  local rc=0
  local output
  output="$(bash "$SCRIPT" --threshold "$value" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "--threshold $value should have been rejected, but setup.sh exited 0"
  case "$output" in
    *"must be"* | *"requires a value"*) ;;
    *) fail "--threshold $value: rejection message doesn't explain why (got: $output)" ;;
  esac
}

assert_rejected "1.5"
assert_rejected "0"
assert_rejected "-0.5"
assert_rejected "abc"
assert_rejected ""

# --- an in-range value must be accepted, run under an isolated HOME so the
#     rest of setup.sh (runtime helpers, CodexBar config) never touches the real
#     machine ---
FAKE_HOME="$TMP_DIR/home"
mkdir -p "$FAKE_HOME"
RC=0
OUTPUT="$(HOME="$FAKE_HOME" bash "$SCRIPT" --threshold 0.85 2>&1)" || RC=$?
[ "$RC" -eq 0 ] || fail "--threshold 0.85 should have been accepted, got exit $RC (output: $OUTPUT)"

# --- the --threshold=<value> form must parse the same way ---
RC=0
HOME="$FAKE_HOME" bash "$SCRIPT" --threshold=0.85 >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "--threshold=0.85 should have been accepted, got exit $RC"

# --- omitting --threshold must default to a valid value (0.9) and not fail ---
RC=0
HOME="$FAKE_HOME" bash "$SCRIPT" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "omitting --threshold should default successfully, got exit $RC"

# --- XDG base directories must be absolute, and rejection happens before writes ---
for variable in XDG_DATA_HOME XDG_STATE_HOME; do
  BAD_HOME="$TMP_DIR/bad-${variable}"
  RC=0
  OUTPUT="$(env HOME="$BAD_HOME" "$variable=relative/path" bash "$SCRIPT" 2>&1)" || RC=$?
  [ "$RC" -ne 0 ] || fail "$variable with a relative path should be rejected"
  case "$OUTPUT" in
    *"$variable must be an absolute path"*) ;;
    *) fail "$variable rejection did not explain the absolute-path requirement" ;;
  esac
  [ ! -e "$BAD_HOME" ] || fail "$variable rejection should happen before any writes"
done

# --- jq is a required preflight dependency and failure must precede writes ---
NO_JQ_HOME="$TMP_DIR/no-jq-home"
NO_JQ_PATH="$TMP_DIR/no-jq-bin"
mkdir -p "$NO_JQ_PATH"
ln -s "$(command -v awk)" "$NO_JQ_PATH/awk"
RC=0
OUTPUT="$(PATH="$NO_JQ_PATH" HOME="$NO_JQ_HOME" /bin/bash "$SCRIPT" 2>&1)" || RC=$?
[ "$RC" -ne 0 ] || fail "setup should fail when jq is unavailable"
case "$OUTPUT" in
  *"jq is required"*) ;;
  *) fail "missing-jq error did not explain the dependency" ;;
esac
[ ! -e "$NO_JQ_HOME" ] || fail "missing-jq failure should happen before any writes"

echo "codexbar-quota-handoff threshold-validation checks passed"
