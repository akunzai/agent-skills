#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/remove-grok.sh"

fail() {
  echo "codexbar-quota-handoff remove-grok check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_BIN="$TMP_DIR/stub-bin"
mkdir -p "$STUB_BIN"
REAL_JQ="$(command -v jq)" || fail "jq is required to run this test"
ln -s "$REAL_JQ" "$STUB_BIN/jq"

# --- help is side-effect free ---
HELP_HOME="$TMP_DIR/help-home"
HOME="$HELP_HOME" bash "$SCRIPT" --help >/dev/null
[ ! -e "$HELP_HOME" ] || fail "--help created files"

# --- owned hooks and the grok CodexBar rule are removed; other rules stay ---
FAKE_HOME="$TMP_DIR/home"
mkdir -p "$FAKE_HOME/.codexbar" "$FAKE_HOME/.grok/hooks" \
  "$FAKE_HOME/xdg-data/codexbar-quota-handoff/scripts"
touch "$FAKE_HOME/.grok/hooks/codexbar-quota-reminder.sh" \
  "$FAKE_HOME/xdg-data/codexbar-quota-handoff/scripts/codexbar-quota-flag.sh"
echo '{"hooks":{"Stop":[]}}' >"$FAKE_HOME/.grok/hooks/codexbar-quota-handoff.json"
echo '{"hooks":{"SessionStart":[]}}' >"$FAKE_HOME/.grok/hooks/herdr.json"
cat >"$FAKE_HOME/.codexbar/config.json" <<'EOF'
{"hooks":{"enabled":true,"events":[
  {"id":"agent-skills-codexbar-quota-handoff-claude","provider":"claude"},
  {"id":"agent-skills-codexbar-quota-handoff-grok","provider":"grok"},
  {"id":"someone-elses-rule","provider":"claude"}
]}}
EOF

OUTPUT="$(
  PATH="$STUB_BIN:/usr/bin:/bin" HOME="$FAKE_HOME" \
    XDG_DATA_HOME="$FAKE_HOME/xdg-data" bash "$SCRIPT"
)"
[ ! -e "$FAKE_HOME/.grok/hooks/codexbar-quota-handoff.json" ] \
  || fail "owned Grok global hook was not removed"
[ ! -e "$FAKE_HOME/.grok/hooks/codexbar-quota-reminder.sh" ] \
  || fail "owned Grok reminder script was not removed"
[ -f "$FAKE_HOME/.grok/hooks/herdr.json" ] \
  || fail "remove-grok removed an unrelated Grok hook file"
[ -f "$FAKE_HOME/xdg-data/codexbar-quota-handoff/scripts/codexbar-quota-flag.sh" ] \
  || fail "remove-grok must not remove shared runtime helpers"
IDS="$(jq -r '.hooks.events[].id' "$FAKE_HOME/.codexbar/config.json" | sort | paste -sd, -)"
[ "$IDS" = "agent-skills-codexbar-quota-handoff-claude,someone-elses-rule" ] \
  || fail "remove-grok should drop only the grok CodexBar rule, got: $IDS"
case "$OUTPUT" in
  *"grok plugin marketplace remove akunzai-agent-skills"*) ;;
  *) fail "without grok on PATH, output should print the marketplace remove command (got: $OUTPUT)" ;;
esac
case "$OUTPUT" in
  *"Re-run with --yes"*) fail "without grok on PATH, should not offer --yes (got: $OUTPUT)" ;;
esac

# --- grok on PATH without --yes prints the command and does not run it ---
GROK_BIN="$TMP_DIR/grok-bin"
mkdir -p "$GROK_BIN"
GROK_LOG="$TMP_DIR/grok.log"
cat >"$GROK_BIN/grok" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$GROK_LOG"
exit 0
STUB
chmod +x "$GROK_BIN/grok"
PRINT_HOME="$TMP_DIR/print-home"
mkdir -p "$PRINT_HOME"
OUTPUT="$(PATH="$GROK_BIN:$STUB_BIN:/usr/bin:/bin" HOME="$PRINT_HOME" bash "$SCRIPT")"
[ ! -s "$GROK_LOG" ] || fail "without --yes, grok CLI should not be invoked"
case "$OUTPUT" in
  *"Re-run with --yes"*) ;;
  *) fail "with grok on PATH, output should mention --yes (got: $OUTPUT)" ;;
esac

# --- --yes runs the marketplace remove command ---
: >"$GROK_LOG"
YES_HOME="$TMP_DIR/yes-home"
mkdir -p "$YES_HOME"
PATH="$GROK_BIN:$STUB_BIN:/usr/bin:/bin" HOME="$YES_HOME" bash "$SCRIPT" --yes >/dev/null
[ "$(cat "$GROK_LOG")" = "plugin marketplace remove akunzai-agent-skills" ] \
  || fail "--yes should run grok plugin marketplace remove, got: $(cat "$GROK_LOG")"

echo "codexbar-quota-handoff remove-grok checks passed"
