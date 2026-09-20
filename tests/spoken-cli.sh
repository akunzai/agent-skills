#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/spoken-tts/scripts/spoken.sh"

fail() {
  echo "spoken cli check failed: $*" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "scripts/spoken.sh is missing or not executable"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$TMP_DIR/config"
export XDG_STATE_HOME="$TMP_DIR/state"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

STUB_BIN="$TMP_DIR/bin"
SAY_LOG="$TMP_DIR/say.log"
EDGE_LOG="$TMP_DIR/edge.log"
mkdir -p "$STUB_BIN"

py() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  else
    python "$@"
  fi
}

cat >"$STUB_BIN/say" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "-v" && "\${2:-}" == "?" ]]; then
  printf '%s\n' \\
    'Meijia              zh_TW    # hi' \\
    'Ting-Ting           zh_TW    # hi' \\
    'Samantha            en_US    # hi'
  exit 0
fi
printf '%s\n' "\$*" >>"$SAY_LOG"
STUB
chmod +x "$STUB_BIN/say"

cat >"$STUB_BIN/edge-tts" <<STUB
#!/usr/bin/env bash
if [[ "\${EDGE_TTS_FAIL:-}" == 1 ]]; then
  exit 1
fi
printf '%s\n' "\$*" >>"$EDGE_LOG"
STUB
chmod +x "$STUB_BIN/edge-tts"

export PATH="$STUB_BIN:/usr/bin:/bin"
export SPOKEN_SYNC=1
export SPOKEN_NATIVE_PROVIDER=say
unset CURSOR_INVOKED_AS COPILOT_CLI PLUGIN_ROOT SPOKEN_SESSION_ID CLAUDE_CODE_SESSION_ID || true

run() {
  bash "$SCRIPT" "$@"
}

# --- on without session id writes pending, does not enable a session ---
out="$(run on 2>&1)" || fail "on without session id should write pending: $out"
[ -f "$XDG_STATE_HOME/spoken-tts/pending" ] || fail "pending flag was not written"
sessions="$(find "$XDG_STATE_HOME/spoken-tts/sessions" -type f 2>/dev/null | wc -l | tr -d ' \t\r')"
[ "$sessions" = "0" ] || fail "on without session id enabled a session"

# --- hook-prompt claims pending and injects rules ---
prompt_json='{"session_id":"sess-1","hook_event_name":"UserPromptSubmit"}'
inject="$(printf '%s' "$prompt_json" | run hook-prompt)"
[ ! -f "$XDG_STATE_HOME/spoken-tts/pending" ] || fail "pending was not claimed"
[ -f "$XDG_STATE_HOME/spoken-tts/sessions/sess-1" ] || fail "session flag was not created"
printf '%s' "$inject" | grep -q '<spoken>' || fail "hook-prompt did not inject spoken rules: $inject"
printf '%s' "$inject" | grep -q 'hookSpecificOutput' \
  || fail "Claude hook-prompt should use hookSpecificOutput: $inject"

# --- on with session id enables that session ---
run off --session-id sess-1 >/dev/null
[ ! -f "$XDG_STATE_HOME/spoken-tts/sessions/sess-1" ] || fail "off did not clear the session"
run on --session-id sess-1 >/dev/null
[ -f "$XDG_STATE_HOME/spoken-tts/sessions/sess-1" ] || fail "on --session-id did not enable"

# --- toggle ---
run toggle --session-id sess-1 >/dev/null
[ ! -f "$XDG_STATE_HOME/spoken-tts/sessions/sess-1" ] || fail "toggle did not disable"
run toggle --session-id sess-1 >/dev/null
[ -f "$XDG_STATE_HOME/spoken-tts/sessions/sess-1" ] || fail "toggle did not enable"

# --- setup recommends edge-tts even when native say exists ---
[ "$(run default-provider)" = "edge-tts" ] \
  || fail "default-provider should recommend edge-tts (got: $(run default-provider))"

# --- Linux-native refusal is the default-provider path when native is empty ---
native_out="$(SPOKEN_NATIVE_PROVIDER='' run default-provider)"
[ "$native_out" = "edge-tts" ] || fail "empty native should default to edge-tts (got: $native_out)"
set +e
SPOKEN_NATIVE_PROVIDER='' run on --session-id linux-1 >/dev/null 2>"$TMP_DIR/on-linux.err"
on_status=$?
set -e
[ "$on_status" -ne 0 ] || fail "on without config should fail when there is no native provider"
grep -q setup "$TMP_DIR/on-linux.err" || fail "on without native should mention setup"

# --- voices: recommended first ---
voices_out="$(run voices --provider say --locale zh-TW | tr -d '\r')"
first_voice="$(printf '%s\n' "$voices_out" | head -n 1)"
[ "$first_voice" = "Meijia" ] || fail "zh-TW say voices should start with Meijia (got: $first_voice)"
printf '%s\n' "$voices_out" | grep -qx 'Ting-Ting' || fail "zh-TW say voices missing Ting-Ting"

edge_voices="$(run voices --provider edge-tts --locale zh-TW | tr -d '\r')"
edge_first="$(printf '%s\n' "$edge_voices" | head -n 1)"
[ "$edge_first" = "zh-TW-HsiaoChenNeural" ] \
  || fail "zh-TW edge-tts should start with HsiaoChen (got: $edge_first)"

# --- empty voices fail ---
set +e
run voices --provider say --locale xx-XX >/dev/null 2>"$TMP_DIR/voices-empty.err"
empty_status=$?
set -e
[ "$empty_status" -ne 0 ] || fail "empty voice list should fail"

# --- config-write + show ---
run config-write --provider say --locale zh-TW --voice Meijia >/dev/null
[ -f "$XDG_CONFIG_HOME/spoken-tts/config.json" ] \
  || fail "config-write should land in spoken-tts"
show="$(run config-show)"
printf '%s' "$show" | jq -e '.provider == "say" and .locale == "zh-TW" and .voice == "Meijia"' >/dev/null \
  || fail "config-show mismatch: $show"

# --- leftover spoken/config.json migrates once ---
rm -rf "$XDG_CONFIG_HOME/spoken-tts" "$XDG_CONFIG_HOME/spoken"
mkdir -p "$XDG_CONFIG_HOME/spoken"
printf '%s\n' '{"provider":"edge-tts","locale":"zh-TW","voice":"zh-TW-HsiaoChenNeural"}' \
  >"$XDG_CONFIG_HOME/spoken/config.json"
migrated="$(run config-show)"
printf '%s' "$migrated" | jq -e '.provider == "edge-tts" and .voice == "zh-TW-HsiaoChenNeural"' >/dev/null \
  || fail "config-show should migrate leftover spoken config: $migrated"
[ -f "$XDG_CONFIG_HOME/spoken-tts/config.json" ] || fail "migrated config missing at spoken-tts"
[ ! -f "$XDG_CONFIG_HOME/spoken/config.json" ] || fail "legacy spoken config.json should be removed"

# --- existing spoken-tts config is not replaced by leftover spoken ---
mkdir -p "$XDG_CONFIG_HOME/spoken"
printf '%s\n' '{"provider":"say","locale":"en-US","voice":"Samantha"}' \
  >"$XDG_CONFIG_HOME/spoken/config.json"
kept="$(run config-show)"
printf '%s' "$kept" | jq -e '.provider == "edge-tts"' >/dev/null \
  || fail "existing spoken-tts config should win over leftover spoken: $kept"
[ -f "$XDG_CONFIG_HOME/spoken/config.json" ] \
  || fail "unmigrated leftover spoken config should stay when new config exists"

run config-write --provider say --locale zh-TW --voice Meijia >/dev/null

# --- hook-stop speaks last spoken tag ---
rm -f "$SAY_LOG"
stop_json="$(jq -n --arg msg $'hello\n<spoken>done now</spoken>\n' \
  '{session_id:"sess-1",hook_event_name:"Stop",last_assistant_message:$msg}')"
printf '%s' "$stop_json" | run hook-stop
[ -f "$SAY_LOG" ] || fail "hook-stop did not invoke say"
grep -q 'done now' "$SAY_LOG" || fail "hook-stop did not speak the tag text: $(cat "$SAY_LOG")"

# --- missing tag is silence ---
rm -f "$SAY_LOG"
quiet_json="$(jq -n --arg msg 'just a reply' \
  '{session_id:"sess-1",hook_event_name:"Stop",last_assistant_message:$msg}')"
printf '%s' "$quiet_json" | run hook-stop
[ ! -f "$SAY_LOG" ] || fail "missing tag should not speak: $(cat "$SAY_LOG")"

# --- disabled session is silence ---
run off --session-id sess-1 >/dev/null
rm -f "$SAY_LOG"
printf '%s' "$stop_json" | run hook-stop
[ ! -f "$SAY_LOG" ] || fail "disabled session should not speak"

run on --session-id sess-1 >/dev/null

# --- SubagentStop is silence ---
rm -f "$SAY_LOG"
sub_json="$(jq -n --arg msg '<spoken>worker done</spoken>' \
  '{session_id:"sess-1",hook_event_name:"SubagentStop",last_assistant_message:$msg}')"
printf '%s' "$sub_json" | run hook-stop
[ ! -f "$SAY_LOG" ] || fail "SubagentStop should not speak"

# --- last of two tags wins ---
rm -f "$SAY_LOG"
two_json="$(jq -n --arg msg '<spoken>first</spoken> body <spoken>second</spoken>' \
  '{session_id:"sess-1",hook_event_name:"Stop",last_assistant_message:$msg}')"
printf '%s' "$two_json" | run hook-stop
grep -q 'second' "$SAY_LOG" || fail "should speak the last tag: $(cat "$SAY_LOG")"
grep -q 'first' "$SAY_LOG" && fail "should not speak the first tag: $(cat "$SAY_LOG")"

# --- zh locale truncates to 80 ---
rm -f "$SAY_LOG"
long81="$(printf '字%.0s' {1..81})"
[ "${#long81}" -eq 81 ] || long81="$(py -c 'print("字"*81)')"
trunc_json="$(jq -n --arg msg "<spoken>${long81}</spoken>" \
  '{session_id:"sess-1",hook_event_name:"Stop",last_assistant_message:$msg}')"
printf '%s' "$trunc_json" | run hook-stop
# say stub logs "$*" so "-v Meijia TEXT"
logged="$(awk '{print substr($0, index($0,$3))}' "$SAY_LOG")"
logged_len="$(printf '%s' "$logged" | py -c 'import sys; print(len(sys.stdin.read()))')"
[ "$logged_len" -eq 80 ] || fail "zh spoken tag should truncate to 80 (got $logged_len): $logged"

run config-write --provider say --locale en-US --voice Samantha >/dev/null
rm -f "$SAY_LOG"
long161="$(py -c 'print("a"*161)')"
trunc_en="$(jq -n --arg msg "<spoken>${long161}</spoken>" \
  '{session_id:"sess-1",hook_event_name:"Stop",last_assistant_message:$msg}')"
printf '%s' "$trunc_en" | run hook-stop
logged_en="$(awk '{print substr($0, index($0,$3))}' "$SAY_LOG")"
logged_en_len="$(printf '%s' "$logged_en" | py -c 'import sys; print(len(sys.stdin.read()))')"
[ "$logged_en_len" -eq 160 ] || fail "en spoken tag should truncate to 160 (got $logged_en_len)"
run config-write --provider say --locale zh-TW --voice Meijia >/dev/null

# --- speak cap 5000 ---
rm -f "$SAY_LOG"
long5001="$(py -c 'print("a"*5001)')"
set +e
printf '%s' "$long5001" | run speak >/dev/null 2>"$TMP_DIR/speak-cap.err"
speak_status=$?
set -e
[ "$speak_status" -eq 0 ] || fail "speak should succeed after truncating"
grep -q '5000' "$TMP_DIR/speak-cap.err" || fail "speak should mention the 5000 cap on stderr"
capped_len="$(py -c 'import sys; print(len(open(sys.argv[1]).read().split(" ",2)[-1].rstrip("\n")))' "$SAY_LOG")"
[ "$capped_len" -eq 5000 ] || fail "speak should send 5000 chars (got $capped_len)"

# --- speak does not require session on ---
run off --session-id sess-1 >/dev/null
rm -f "$SAY_LOG"
printf 'named passage' | run speak
grep -q 'named passage' "$SAY_LOG" || fail "speak without session should still talk"

set +e
printf '' | run speak >/dev/null 2>"$TMP_DIR/speak-empty.err"
empty_speak=$?
set -e
[ "$empty_speak" -ne 0 ] || fail "speak with empty stdin should fail"
grep -q 'pipe text' "$TMP_DIR/speak-empty.err" \
  || fail "empty speak should ask for piped text: $(cat "$TMP_DIR/speak-empty.err")"

# CLI speak waits even when the test harness is not forcing SPOKEN_SYNC.
rm -f "$XDG_STATE_HOME/spoken-tts/player.pid"
(
  unset SPOKEN_SYNC
  printf 'cli waits' | run speak
)
[ ! -f "$XDG_STATE_HOME/spoken-tts/player.pid" ] \
  || fail "CLI speak should wait inline, not leave a background player.pid"

# Isolated PATH: Linux CI has no afplay/mpv; macOS /usr/bin/afplay must not hide that.
NO_PLAYER="$TMP_DIR/no-player"
mkdir -p "$NO_PLAYER"
for bin in bash jq mktemp uname awk mkdir rm cat kill; do
  src="$(command -v "$bin")" || fail "missing $bin for no-player PATH"
  ln -s "$src" "$NO_PLAYER/$bin"
done

# --- edge-tts failure falls back to native say ---
run config-write --provider edge-tts --locale zh-TW --voice zh-TW-HsiaoChenNeural >/dev/null
rm -f "$SAY_LOG" "$EDGE_LOG"
set +e
printf 'hello fallback' | env PATH="$NO_PLAYER:$STUB_BIN" \
  SPOKEN_SYNC=1 SPOKEN_NATIVE_PROVIDER=say EDGE_TTS_FAIL=1 \
  bash "$SCRIPT" speak >/dev/null 2>"$TMP_DIR/fallback.err"
set -e
[ -f "$SAY_LOG" ] || fail "fallback should invoke say: $(cat "$TMP_DIR/fallback.err")"
grep -q 'hello fallback' "$SAY_LOG" || fail "fallback say log missing text: $(cat "$SAY_LOG")"
grep -qi 'edge-tts failed' "$TMP_DIR/fallback.err" \
  || fail "fallback should log on stderr: $(cat "$TMP_DIR/fallback.err")"

# --- edge-tts without an audio player explains how to install one ---
set +e
printf 'silent' | env PATH="$NO_PLAYER:$STUB_BIN" SPOKEN_NATIVE_PROVIDER='' \
  bash "$SCRIPT" speak >"$TMP_DIR/player.out" 2>"$TMP_DIR/player.err"
player_status=$?
set -e
player_err="$(cat "$TMP_DIR/player.err")"
[ "$player_status" -ne 0 ] || fail "speak without a player should fail: $player_err"
printf '%s' "$player_err" | grep -q 'no audio player' \
  || fail "speak without a player should name the gap: $player_err"
printf '%s' "$player_err" | grep -q 'mpv' \
  || fail "speak without a player should mention mpv: $player_err"

# --- Copilot additional_context shape ---
run on --session-id sess-1 >/dev/null
copilot_out="$(printf '%s' "$prompt_json" | COPILOT_CLI=1 run hook-prompt)"
printf '%s' "$copilot_out" | jq -e '.additional_context' >/dev/null \
  || fail "Copilot hook-prompt should print additional_context: $copilot_out"
cursor_out="$(printf '%s' "$prompt_json" | CURSOR_INVOKED_AS=1 run hook-prompt)"
printf '%s' "$cursor_out" | jq -e '.additional_context' >/dev/null \
  || fail "Cursor hook-prompt should print additional_context: $cursor_out"

# --- hook-prompt stops playback ---
sleep 30 &
sleep_pid=$!
mkdir -p "$XDG_STATE_HOME/spoken-tts"
echo "$sleep_pid" >"$XDG_STATE_HOME/spoken-tts/player.pid"
printf '%s' "$prompt_json" | run hook-prompt >/dev/null
if kill -0 "$sleep_pid" 2>/dev/null; then
  kill "$sleep_pid" 2>/dev/null || true
  fail "hook-prompt did not stop playback pid $sleep_pid"
fi

# --- locale recommend ---
[ "$(LC_ALL=ja_JP.UTF-8 LANG=en_US.UTF-8 run locale-recommend | tr -d '\r')" = "ja-JP" ] \
  || fail "LC_ALL should win over LANG"
NO_DEFAULTS="$TMP_DIR/no-defaults"
mkdir -p "$NO_DEFAULTS"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$NO_DEFAULTS/defaults"
chmod +x "$NO_DEFAULTS/defaults"
lang_out="$(
  unset LC_ALL
  PATH="$NO_DEFAULTS:$PATH"
  LANG=zh_TW.UTF-8
  run locale-recommend | tr -d '\r'
)"
[ "$lang_out" = "zh-TW" ] || fail "zh_TW LANG should recommend zh-TW when LC_ALL is unset"
if [ "$(uname -s)" = Darwin ]; then
  cat >"$STUB_BIN/defaults" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = read ] && [ "${2:-}" = -g ] && [ "${3:-}" = AppleLanguages ]; then
  printf '%s\n' '(' '    "zh-Hant-TW",' '    "en-TW"' ')'
  exit 0
fi
exit 1
STUB
  chmod +x "$STUB_BIN/defaults"
  ui_out="$(
    unset LC_ALL
    LANG=en_US.UTF-8
    run locale-recommend | tr -d '\r'
  )"
  rm -f "$STUB_BIN/defaults"
  [ "$ui_out" = "zh-TW" ] || fail "macOS AppleLanguages should win over LANG"
fi
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    cat >"$STUB_BIN/powershell.exe" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *Get-WinUILanguageOverride*) exit 0 ;;
  *Get-WinUserLanguageList*)
    printf '%s\n' 'en-US' 'zh-Hant-TW'
    exit 0
    ;;
esac
exit 1
STUB
    chmod +x "$STUB_BIN/powershell.exe"
    ui_out="$(
      unset LC_ALL
      LANG=en_US.UTF-8
      run locale-recommend | tr -d '\r'
    )"
    rm -f "$STUB_BIN/powershell.exe"
    [ "$ui_out" = "zh-TW" ] \
      || fail "Windows language list should prefer zh-Hant-TW over leading en-US"
    ;;
esac

# --- ensure-edge-tts prefers mise, then uv, then pipx ---
ENSURE_BIN="$TMP_DIR/ensure-bin"
MISE_LOG="$TMP_DIR/mise.log"
UV_LOG="$TMP_DIR/uv.log"
PIPX_LOG="$TMP_DIR/pipx.log"
mkdir -p "$ENSURE_BIN"

cat >"$ENSURE_BIN/mise" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$MISE_LOG"
mkdir -p "$HOME/.local/share/mise/shims"
cat >"$HOME/.local/share/mise/shims/edge-tts" <<'BIN'
#!/usr/bin/env bash
exit 0
BIN
chmod +x "$HOME/.local/share/mise/shims/edge-tts"
exit 0
STUB
cat >"$ENSURE_BIN/uv" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$UV_LOG"
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/edge-tts" <<'BIN'
#!/usr/bin/env bash
exit 0
BIN
chmod +x "$HOME/.local/bin/edge-tts"
exit 0
STUB
cat >"$ENSURE_BIN/pipx" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$PIPX_LOG"
exit 0
STUB
chmod +x "$ENSURE_BIN/mise" "$ENSURE_BIN/uv" "$ENSURE_BIN/pipx"

rm -f "$MISE_LOG" "$UV_LOG" "$PIPX_LOG"
rm -rf "$HOME/.local"
PATH="$ENSURE_BIN:/usr/bin:/bin" run ensure-edge-tts >/dev/null \
  || fail "ensure-edge-tts should succeed via mise"
[ "$(cat "$MISE_LOG")" = "use -g -y pipx:edge-tts" ] \
  || fail "ensure-edge-tts should mise use -g -y pipx:edge-tts: $(cat "$MISE_LOG")"
[ ! -f "$UV_LOG" ] || fail "mise path should not call uv: $(cat "$UV_LOG")"
[ ! -f "$PIPX_LOG" ] || fail "mise path should not call pipx: $(cat "$PIPX_LOG")"

already="$(PATH="$STUB_BIN:$ENSURE_BIN:/usr/bin:/bin" run ensure-edge-tts)"
printf '%s' "$already" | grep -q 'already on PATH' \
  || fail "ensure-edge-tts should skip install when edge-tts is on PATH: $already"
[ ! -f "$UV_LOG" ] || fail "already-on-PATH should not call uv"

rm -f "$ENSURE_BIN/mise" "$MISE_LOG" "$UV_LOG" "$PIPX_LOG"
rm -rf "$HOME/.local"
PATH="$ENSURE_BIN:/usr/bin:/bin" run ensure-edge-tts >/dev/null \
  || fail "ensure-edge-tts should succeed via uv when mise is absent"
[ -f "$UV_LOG" ] || fail "uv fallback was not invoked"
grep -q 'tool install edge-tts' "$UV_LOG" || fail "uv fallback args: $(cat "$UV_LOG")"
[ ! -f "$PIPX_LOG" ] || fail "uv path should not call pipx"

rm -f "$ENSURE_BIN/uv" "$UV_LOG" "$PIPX_LOG"
rm -rf "$HOME/.local"
set +e
PATH="/usr/bin:/bin" run ensure-edge-tts >/dev/null 2>"$TMP_DIR/ensure.err"
ensure_status=$?
set -e
[ "$ensure_status" -ne 0 ] || fail "ensure-edge-tts should refuse when no installer exists"
grep -q 'mise use -g -y pipx:edge-tts' "$TMP_DIR/ensure.err" \
  || fail "refusal should mention mise: $(cat "$TMP_DIR/ensure.err")"

echo "spoken cli checks passed"
