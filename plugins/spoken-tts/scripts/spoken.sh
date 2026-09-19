#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINE_FILE="$PLUGIN_ROOT/skills/spoken/references/line.md"

detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos\n' ;;
    *) printf 'linux\n' ;;
  esac
}

is_windows() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

is_absolute() {
  [[ "$1" == /* ]]
}

resolve_xdg() {
  local value="$1" fallback="$2"
  if is_absolute "$value"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

config_home="$(resolve_xdg "${XDG_CONFIG_HOME:-$HOME/.config}" "$HOME/.config")"
state_home="$(resolve_xdg "${XDG_STATE_HOME:-$HOME/.local/state}" "$HOME/.local/state")"

CONFIG_DIR="$config_home/spoken-tts"
STATE_DIR="$state_home/spoken-tts"
CONFIG_FILE="$CONFIG_DIR/config.json"
LEGACY_CONFIG_DIR="$config_home/spoken"
LEGACY_CONFIG_FILE="$LEGACY_CONFIG_DIR/config.json"
SESSIONS_DIR="$STATE_DIR/sessions"
PENDING_FILE="$STATE_DIR/pending"
PID_FILE="$STATE_DIR/player.pid"

prepend_user_tool_paths() {
  local shims="${HOME}/.local/share/mise/shims"
  local bin="${HOME}/.local/bin"
  [[ -d "$shims" ]] && PATH="$shims:$PATH"
  [[ -d "$bin" ]] && PATH="$bin:$PATH"
  export PATH
}

prepend_user_tool_paths

usage() {
  cat <<'EOF'
Usage: spoken.sh <command> [options]

Commands:
  on [--session-id ID]
  off [--session-id ID]
  toggle [--session-id ID]
  status
  default-provider
  locale-recommend
  voices --provider NAME --locale LOCALE
  config-write --provider NAME --locale LOCALE --voice NAME
  config-show
  speak
  test
  stop
  ensure-edge-tts
  hook-stop
  hook-prompt
EOF
}

ensure_state_dirs() {
  mkdir -p "$SESSIONS_DIR"
}

absolute_config() {
  mkdir -p "$CONFIG_DIR"
}

make_temp() {
  mktemp "${TMPDIR:-/tmp}/spoken.XXXXXX"
}

native_provider() {
  if [[ -n "${SPOKEN_NATIVE_PROVIDER+x}" ]]; then
    printf '%s\n' "$SPOKEN_NATIVE_PROVIDER"
    return
  fi
  if [[ "$(detect_os)" == macos ]]; then
    printf 'say\n'
  else
    printf '\n'
  fi
}

recommend_voice() {
  local provider="$1" locale="$2"
  case "$provider:$locale" in
    say:zh-TW) printf 'Meijia\n' ;;
    say:zh-CN) printf 'Tingting\n' ;;
    say:en-US) printf 'Samantha\n' ;;
    say:en-GB) printf 'Daniel\n' ;;
    say:ja-JP) printf 'Kyoko\n' ;;
    edge-tts:zh-TW) printf 'zh-TW-HsiaoChenNeural\n' ;;
    edge-tts:zh-CN) printf 'zh-CN-XiaoxiaoNeural\n' ;;
    edge-tts:en-US) printf 'en-US-AriaNeural\n' ;;
    edge-tts:en-GB) printf 'en-GB-SoniaNeural\n' ;;
    edge-tts:ja-JP) printf 'ja-JP-NanamiNeural\n' ;;
    *) printf '\n' ;;
  esac
}

edge_tts_catalog() {
  local locale="$1"
  case "$locale" in
    zh-TW)
      printf '%s\n' zh-TW-HsiaoChenNeural zh-TW-HsiaoYuNeural zh-TW-YunJheNeural
      ;;
    zh-CN)
      printf '%s\n' zh-CN-XiaoxiaoNeural zh-CN-YunxiNeural zh-CN-XiaoyiNeural
      ;;
    en-US)
      printf '%s\n' en-US-AriaNeural en-US-JennyNeural en-US-GuyNeural
      ;;
    en-GB)
      printf '%s\n' en-GB-SoniaNeural en-GB-RyanNeural en-GB-LibbyNeural
      ;;
    ja-JP)
      printf '%s\n' ja-JP-NanamiNeural ja-JP-KeitaNeural
      ;;
  esac
}

say_locale_code() {
  local locale="$1"
  printf '%s\n' "${locale//-/_}"
}

list_say_voices() {
  local locale="$1" code
  code="$(say_locale_code "$locale")"
  command -v say >/dev/null 2>&1 || return 0
  say -v '?' 2>/dev/null | awk -v code="$code" '
    $2 == code { print $1 }
  '
}

list_voices_for() {
  local provider="$1" locale="$2"
  case "$provider" in
    say) list_say_voices "$locale" ;;
    edge-tts) edge_tts_catalog "$locale" ;;
  esac
}

print_voices_recommended_first() {
  local provider="$1" locale="$2"
  local recommended voices
  recommended="$(recommend_voice "$provider" "$locale")"
  voices="$(list_voices_for "$provider" "$locale" | awk 'NF')"
  if [[ -z "$voices" ]]; then
    return 1
  fi
  if [[ -n "$recommended" ]] && printf '%s\n' "$voices" | grep -qx "$recommended"; then
    printf '%s\n' "$recommended"
    printf '%s\n' "$voices" | grep -vx "$recommended" || true
  else
    printf '%s\n' "$voices"
  fi
}

migrate_legacy_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    return
  fi
  [[ -f "$LEGACY_CONFIG_FILE" ]] || return 0
  mkdir -p "$CONFIG_DIR"
  cp "$LEGACY_CONFIG_FILE" "$CONFIG_FILE"
  rm -f "$LEGACY_CONFIG_FILE"
  rmdir "$LEGACY_CONFIG_DIR" 2>/dev/null || true
}

load_config() {
  PROVIDER=""
  LOCALE=""
  VOICE=""
  migrate_legacy_config
  if [[ -f "$CONFIG_FILE" ]]; then
    PROVIDER="$(jq -r '.provider // empty' "$CONFIG_FILE")"
    LOCALE="$(jq -r '.locale // empty' "$CONFIG_FILE")"
    VOICE="$(jq -r '.voice // empty' "$CONFIG_FILE")"
  fi
}

session_id_from_args() {
  SESSION_ID="${SPOKEN_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id)
        SESSION_ID="${2:-}"
        shift 2
        ;;
      --session-id=*)
        SESSION_ID="${1#--session-id=}"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
}

enable_session() {
  local id="$1"
  ensure_state_dirs
  : >"$SESSIONS_DIR/$id"
  rm -f "$PENDING_FILE"
}

disable_session() {
  local id="$1"
  rm -f "$SESSIONS_DIR/$id"
  stop_playback
}

session_enabled() {
  local id="$1"
  [[ -n "$id" && -f "$SESSIONS_DIR/$id" ]]
}

cmd_default_provider() {
  printf 'edge-tts\n'
}

locale_from_lang() {
  local lang="$1"
  case "$lang" in
    zh_TW*|zh-TW*|zh_Hant*|zh-Hant*) printf 'zh-TW\n' ;;
    zh_CN*|zh-CN*|zh_HK*|zh-HK*|zh_Hans*|zh-Hans*) printf 'zh-CN\n' ;;
    en_GB*|en-GB*) printf 'en-GB\n' ;;
    ja*) printf 'ja-JP\n' ;;
    en*) printf 'en-US\n' ;;
    *) return 1 ;;
  esac
}

# Cursor and Git Bash often set LANG=en_US; OS UI may differ. LC_ALL wins.
macos_ui_lang() {
  [[ "$(detect_os)" == macos ]] || return 1
  command -v defaults >/dev/null 2>&1 || return 1
  local raw lang
  raw="$(defaults read -g AppleLanguages 2>/dev/null || true)"
  lang="$(printf '%s\n' "$raw" | awk -F'"' '/"/{print $2; exit}')"
  if [[ -n "$lang" ]]; then
    printf '%s\n' "$lang"
    return 0
  fi
  raw="$(defaults read -g AppleLocale 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1
  printf '%s\n' "$raw"
}

trim_win_lang() {
  printf '%s' "$1" | tr -d '\000\r' | awk 'NF{print; exit}'
}

# Prefer a mapped non-English tag. LanguageList[0] is preference/IME order,
# not Windows display language (en-US then zh-Hant-TW is common).
win_best_tag() {
  local tag mapped first=""
  while IFS= read -r tag || [[ -n "$tag" ]]; do
    tag="$(trim_win_lang "$tag")"
    [[ -n "$tag" ]] || continue
    mapped="$(locale_from_lang "$tag")" || continue
    case "$mapped" in
      en-*)
        [[ -n "$first" ]] || first="$tag"
        ;;
      *)
        printf '%s\n' "$tag"
        return 0
        ;;
    esac
  done
  [[ -n "$first" ]] || return 1
  printf '%s\n' "$first"
}

win_tags_from_reg() {
  awk '/REG_/ {
    for (i = 1; i <= NF; i++)
      if ($i ~ /^[A-Za-z][A-Za-z](-[A-Za-z0-9]+)+$/) print $i
  }'
}

windows_ui_lang() {
  is_windows || return 1
  local raw lang ps=""
  if command -v powershell.exe >/dev/null 2>&1; then
    ps=powershell.exe
  elif command -v powershell >/dev/null 2>&1; then
    ps=powershell
  fi
  if [[ -n "$ps" ]]; then
    raw="$("$ps" -NoProfile -NonInteractive -Command \
      '(Get-WinUILanguageOverride).Name' 2>/dev/null || true)"
    lang="$(trim_win_lang "$raw")"
    if [[ -n "$lang" ]]; then
      printf '%s\n' "$lang"
      return 0
    fi
  fi
  if command -v reg.exe >/dev/null 2>&1; then
    raw="$(reg.exe query 'HKCU\Control Panel\Desktop' /v PreferredUILanguages 2>/dev/null || true)"
    lang="$(printf '%s\n' "$raw" | win_tags_from_reg | win_best_tag)" || lang=""
    if [[ -n "$lang" ]]; then
      printf '%s\n' "$lang"
      return 0
    fi
  fi
  if [[ -n "$ps" ]]; then
    raw="$("$ps" -NoProfile -NonInteractive -Command \
      '(Get-WinUserLanguageList).LanguageTag' 2>/dev/null || true)"
    lang="$(printf '%s\n' "$raw" | tr -d '\000' | win_best_tag)" || lang=""
    if [[ -n "$lang" ]]; then
      printf '%s\n' "$lang"
      return 0
    fi
  fi
  if command -v reg.exe >/dev/null 2>&1; then
    raw="$(reg.exe query 'HKCU\Control Panel\International' /v LocaleName 2>/dev/null || true)"
    lang="$(printf '%s\n' "$raw" | win_tags_from_reg | awk 'NF{print; exit}')"
    lang="$(trim_win_lang "$lang")"
    if [[ -n "$lang" ]]; then
      printf '%s\n' "$lang"
      return 0
    fi
  fi
  return 1
}

cmd_locale_recommend() {
  local lang
  if [[ -n "${LC_ALL:-}" ]] && locale_from_lang "$LC_ALL"; then
    return
  fi
  if lang="$(macos_ui_lang)" && [[ -n "$lang" ]] && locale_from_lang "$lang"; then
    return
  fi
  if lang="$(windows_ui_lang)" && [[ -n "$lang" ]] && locale_from_lang "$lang"; then
    return
  fi
  if [[ -n "${LANG:-}" ]] && locale_from_lang "$LANG"; then
    return
  fi
  printf 'en-US\n'
}

require_native_or_config() {
  load_config
  if [[ -n "$PROVIDER" ]]; then
    return 0
  fi
  if [[ -n "$(native_provider)" ]]; then
    return 0
  fi
  printf 'spoken: no TTS config and no native provider; run /spoken setup\n' >&2
  return 1
}

cmd_on() {
  session_id_from_args "$@"
  require_native_or_config
  ensure_state_dirs
  if [[ -n "$SESSION_ID" ]]; then
    enable_session "$SESSION_ID"
    printf 'spoken enabled for this conversation\n'
    return
  fi
  : >"$PENDING_FILE"
  printf 'spoken: waiting for this conversation'\''s hook to claim enablement\n'
}

cmd_off() {
  session_id_from_args "$@"
  ensure_state_dirs
  stop_playback
  rm -f "$PENDING_FILE"
  if [[ -n "$SESSION_ID" ]]; then
    disable_session "$SESSION_ID"
  fi
  printf 'spoken disabled\n'
}

cmd_toggle() {
  session_id_from_args "$@"
  if [[ -n "$SESSION_ID" ]] && session_enabled "$SESSION_ID"; then
    cmd_off --session-id "$SESSION_ID"
  else
    cmd_on --session-id "${SESSION_ID:-}"
  fi
}

cmd_status() {
  load_config
  session_id_from_args "$@"
  local enabled="no"
  if session_enabled "$SESSION_ID"; then
    enabled="yes"
  elif [[ -f "$PENDING_FILE" ]]; then
    enabled="pending"
  fi
  printf 'enabled: %s\n' "$enabled"
  printf 'session: %s\n' "${SESSION_ID:-}"
  printf 'provider: %s\n' "${PROVIDER:-}"
  printf 'locale: %s\n' "${LOCALE:-}"
  printf 'voice: %s\n' "${VOICE:-}"
}

cmd_voices() {
  local provider="" locale=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="${2:-}"; shift 2 ;;
      --locale) locale="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$provider" && -n "$locale" ]] || {
    printf 'spoken: voices requires --provider and --locale\n' >&2
    return 1
  }
  print_voices_recommended_first "$provider" "$locale"
}

cmd_config_write() {
  local provider="" locale="" voice=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="${2:-}"; shift 2 ;;
      --locale) locale="${2:-}"; shift 2 ;;
      --voice) voice="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$provider" && -n "$locale" && -n "$voice" ]] || {
    printf 'spoken: config-write requires --provider, --locale, and --voice\n' >&2
    return 1
  }
  if ! print_voices_recommended_first "$provider" "$locale" >/dev/null; then
    printf 'spoken: no voices for %s / %s; install a system voice or pick another locale\n' \
      "$provider" "$locale" >&2
    return 1
  fi
  absolute_config
  jq -n --arg provider "$provider" --arg locale "$locale" --arg voice "$voice" \
    '{provider:$provider,locale:$locale,voice:$voice}' >"$CONFIG_FILE"
  printf 'spoken config saved\n'
}

cmd_config_show() {
  migrate_legacy_config
  if [[ ! -f "$CONFIG_FILE" ]]; then
    printf '{}\n'
    return
  fi
  cat "$CONFIG_FILE"
  printf '\n'
}

stop_playback() {
  local pid
  if [[ ! -f "$PID_FILE" ]]; then
    return 0
  fi
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  rm -f "$PID_FILE"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  if command -v pkill >/dev/null 2>&1; then
    pkill -P "$pid" >/dev/null 2>&1 || true
  fi
}

char_len() {
  printf '%s' "$1" | jq -Rs 'length'
}

truncate_chars() {
  local text="$1" limit="$2"
  printf '%s' "$text" | jq -Rs --argjson n "$limit" '.[0:$n]' | jq -r .
}

extract_spoken() {
  local message="$1"
  printf '%s' "$message" | { grep -oE '<spoken>[^<]*</spoken>' || true; } | tail -n 1 \
    | sed -e 's/^<spoken>//' -e 's/<\/spoken>$//'
}

resolve_provider_voice() {
  load_config
  if [[ -z "$PROVIDER" ]]; then
    PROVIDER="$(native_provider)"
  fi
  if [[ -z "$LOCALE" ]]; then
    LOCALE="$(cmd_locale_recommend)"
  fi
  if [[ -z "$VOICE" ]]; then
    VOICE="$(recommend_voice "$PROVIDER" "$LOCALE")"
  fi
}

synth_say() {
  local voice="$1" text="$2"
  if [[ -n "$voice" ]]; then
    say -v "$voice" "$text" || return 1
  else
    say "$text" || return 1
  fi
}

audio_player() {
  if [[ "$(detect_os)" == macos ]]; then
    command -v afplay >/dev/null 2>&1 || return 1
    printf 'afplay\n'
    return 0
  fi
  local p
  for p in mpv ffplay paplay aplay; do
    if command -v "$p" >/dev/null 2>&1; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

print_missing_player() {
  printf 'spoken: no audio player on PATH (need mpv or ffplay)\n' >&2
  if is_windows; then
    printf 'spoken: install with: scoop bucket add extras && scoop install mpv\n' >&2
  else
    printf 'spoken: install mpv, or ffmpeg for ffplay\n' >&2
  fi
}

play_audio() {
  local file="$1" player
  if ! player="$(audio_player)"; then
    print_missing_player
    return 1
  fi
  case "$player" in
    afplay) afplay "$file" ;;
    mpv) mpv --really-quiet --no-terminal "$file" ;;
    ffplay) ffplay -autoexit -nodisp -loglevel quiet "$file" ;;
    paplay) paplay "$file" ;;
    aplay) aplay "$file" ;;
    *) return 1 ;;
  esac
}

synth_edge_tts() {
  local voice="$1" text="$2"
  local tmp media
  if ! audio_player >/dev/null; then
    return 1
  fi
  tmp="$(make_temp)"
  media="${tmp}.mp3"
  edge-tts --voice "$voice" --text "$text" --write-media "$media" || return 1
  play_audio "$media" || return 1
  rm -f "$tmp" "$media"
}

run_synth() {
  local provider="$1" voice="$2" text="$3"
  case "$provider" in
    say) synth_say "$voice" "$text" || return 1 ;;
    edge-tts) synth_edge_tts "$voice" "$text" || return 1 ;;
    *) return 1 ;;
  esac
}

speak_text() {
  local text="$1" limit="${2:-5000}"
  local len fallback_provider fallback_voice
  len="$(char_len "$text")"
  if [[ "$len" -gt "$limit" ]]; then
    printf 'spoken: truncating to %s characters\n' "$limit" >&2
    text="$(truncate_chars "$text" "$limit")"
  fi
  [[ -n "$text" ]] || return 0
  resolve_provider_voice
  [[ -n "$PROVIDER" ]] || {
    printf 'spoken: no provider configured; run /spoken setup\n' >&2
    return 1
  }

  stop_playback

  speak_job() {
    if run_synth "$PROVIDER" "$VOICE" "$text"; then
      return 0
    fi
    fallback_provider="$(native_provider)"
    if [[ -z "$fallback_provider" || "$fallback_provider" == "$PROVIDER" ]]; then
      if [[ "$PROVIDER" == edge-tts ]] && ! audio_player >/dev/null; then
        print_missing_player
        return 1
      fi
      printf 'spoken: %s failed\n' "$PROVIDER" >&2
      return 1
    fi
    fallback_voice="$(recommend_voice "$fallback_provider" "$LOCALE")"
    if [[ -z "$fallback_voice" ]]; then
      fallback_voice="$(list_voices_for "$fallback_provider" "$LOCALE" | awk 'NF{print; exit}')"
    fi
    printf 'spoken: %s failed, using %s/%s\n' "$PROVIDER" "$fallback_provider" "${fallback_voice:-default}" >&2
    run_synth "$fallback_provider" "$fallback_voice" "$text" || {
      printf 'spoken: native fallback failed\n' >&2
      return 1
    }
  }

  if [[ "${SPOKEN_SYNC:-}" == 1 ]]; then
    speak_job
    return
  fi
  ensure_state_dirs
  ( speak_job ) >/dev/null &
  echo $! >"$PID_FILE"
  disown || true
}

cmd_speak() {
  local text
  text="$(cat)"
  if [[ -z "$text" ]]; then
    printf 'spoken: pipe text into speak\n' >&2
    return 1
  fi
  # Git Bash `kill` does not stop Win32 mpv/edge-tts children, so a background
  # speak looks one utterance behind. Wait here; the Stop hook stays async.
  # https://github.com/git-for-windows/msys2-runtime/commit/15f209511985092588b171703e5046eba937b47b
  SPOKEN_SYNC=1 speak_text "$text" 5000
}

cmd_test() {
  load_config
  local sample="Spoken is ready."
  case "${LOCALE:-}" in
    zh-*) sample="語音已設定完成。" ;;
    ja-*) sample="音声の準備ができました。" ;;
  esac
  printf '%s' "$sample" | cmd_speak
}

cmd_stop() {
  stop_playback
}

cmd_ensure_edge_tts() {
  prepend_user_tool_paths
  if command -v edge-tts >/dev/null 2>&1; then
    printf 'edge-tts already on PATH\n'
    return 0
  fi
  if command -v mise >/dev/null 2>&1; then
    if mise use -g -y pipx:edge-tts; then
      prepend_user_tool_paths
      hash -r 2>/dev/null || true
      if command -v edge-tts >/dev/null 2>&1; then
        printf 'edge-tts installed via mise\n'
        return 0
      fi
    fi
  fi
  if command -v uv >/dev/null 2>&1; then
    if uv tool install edge-tts; then
      prepend_user_tool_paths
      hash -r 2>/dev/null || true
      if command -v edge-tts >/dev/null 2>&1; then
        printf 'edge-tts installed via uv\n'
        return 0
      fi
    fi
  fi
  if command -v pipx >/dev/null 2>&1; then
    if pipx install edge-tts; then
      prepend_user_tool_paths
      hash -r 2>/dev/null || true
      if command -v edge-tts >/dev/null 2>&1; then
        printf 'edge-tts installed via pipx\n'
        return 0
      fi
    fi
  fi
  printf 'spoken: install edge-tts with: mise use -g -y pipx:edge-tts\n' >&2
  printf 'spoken: or: uv tool install edge-tts\n' >&2
  printf 'spoken: or: pipx install edge-tts\n' >&2
  return 1
}

summary_limit() {
  local locale="$1"
  case "$locale" in
    zh*|ja*|ko*) printf '80\n' ;;
    *) printf '160\n' ;;
  esac
}

claim_pending() {
  local id="$1"
  [[ -n "$id" && -f "$PENDING_FILE" ]] || return 0
  enable_session "$id"
}

inject_rules() {
  local locale="${1:-en-US}"
  local body
  if [[ -f "$LINE_FILE" ]]; then
    body="$(cat "$LINE_FILE")"
    body="${body//LOCALE/$locale}"
  else
    body="End the reply with one trailing <spoken>one-sentence status in ${locale}</spoken> line."
  fi
  if [[ -n "${CURSOR_INVOKED_AS:-}" || -n "${COPILOT_CLI:-}" ]]; then
    jq -n --arg additional_context "$body" '{additional_context:$additional_context}'
    return
  fi
  jq -n --arg ctx "$body" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
}

cmd_hook_prompt() {
  local input session_id
  input="$(cat)"
  stop_playback
  command -v jq >/dev/null 2>&1 || exit 0
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  claim_pending "$session_id"
  if session_enabled "$session_id"; then
    load_config
    inject_rules "${LOCALE:-$(cmd_locale_recommend)}"
  fi
  exit 0
}

cmd_hook_stop() {
  local input session_id event message tag limit
  input="$(cat)"
  command -v jq >/dev/null 2>&1 || exit 0
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"
  claim_pending "$session_id"
  session_enabled "$session_id" || exit 0
  [[ "$event" != "SubagentStop" ]] || exit 0
  message="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
  tag="$(extract_spoken "$message")"
  [[ -n "$tag" ]] || exit 0
  load_config
  limit="$(summary_limit "${LOCALE:-}")"
  tag="$(truncate_chars "$tag" "$limit")"
  speak_text "$tag" "$limit" || true
  exit 0
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    on) cmd_on "$@" ;;
    off) cmd_off "$@" ;;
    toggle) cmd_toggle "$@" ;;
    status) cmd_status "$@" ;;
    default-provider) cmd_default_provider ;;
    locale-recommend) cmd_locale_recommend ;;
    voices) cmd_voices "$@" ;;
    config-write) cmd_config_write "$@" ;;
    config-show) cmd_config_show ;;
    speak) cmd_speak ;;
    test) cmd_test ;;
    stop) cmd_stop ;;
    ensure-edge-tts) cmd_ensure_edge_tts ;;
    hook-stop) cmd_hook_stop ;;
    hook-prompt) cmd_hook_prompt ;;
    -h|--help|help|"") usage; [[ -n "$cmd" ]] || exit 1 ;;
    *)
      printf 'spoken: unknown command %s\n' "$cmd" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
