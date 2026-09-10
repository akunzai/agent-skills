#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/quota-reminder.sh"
PROJ_MEMORY_PATH="$ROOT_DIR/skills/to-memory/scripts/proj-memory-path.sh"

fail() {
  echo "codexbar-quota-handoff quota-reminder check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Isolated HOME so dest probing never sees the developer's real to-memory skill.
EMPTY_HOME="$TMP_DIR/empty-home"
WORK_DIR="$TMP_DIR/work"
mkdir -p "$EMPTY_HOME" "$WORK_DIR"

# Portable epoch -> ISO8601 UTC formatting (GNU `date -d @epoch`, then
# BSD/macOS `date -r epoch`), so resetAt stays relative to "now" instead of
# a hardcoded date that eventually falls into the past and gets treated as
# stale by the script's own expiry check below.
iso_at() {
  local epoch="$1"
  date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
}

NOW_EPOCH="$(date -u +%s)"
FUTURE_RESET_AT="$(iso_at $((NOW_EPOCH + 3600)))"
PAST_RESET_AT="$(iso_at $((NOW_EPOCH - 3600)))"
TODAY="$(date +%Y-%m-%d)"

FIXTURE="{\"event\":\"quota_low\",\"provider\":\"claude\",\"resetAt\":\"$FUTURE_RESET_AT\",\"timestamp\":\"2026-08-12T15:32:00Z\",\"usagePercent\":0.93,\"window\":\"session\"}"

assert_procedure() {
  local stderr_output="$1" label="$2"
  case "$stderr_output" in
    *session*) ;;
    *) fail "[$label] reminder text does not mention the window (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *93*) ;;
    *) fail "[$label] reminder text does not mention the usage percentage (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *"handoff document"*) ;;
    *) fail "[$label] reminder text does not mention handoff document (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *"Then stop"*) ;;
    *) fail "[$label] reminder text does not mention Then stop (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *"Do not invoke to-memory"*) ;;
    *) fail "[$label] reminder text does not mention Do not invoke to-memory (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *'/handoff'*) fail "[$label] reminder text still mentions /handoff (got: $stderr_output)" ;;
  esac
  # Literal Codex command string, not an expansion.
  # shellcheck disable=SC2016
  local dollar_handoff='$handoff'
  case "$stderr_output" in
    *"$dollar_handoff"*) fail "[$label] reminder text still mentions \$handoff (got: $stderr_output)" ;;
  esac
}

run_reminder() {
  local home="$1" work="$2" flag_path="$3"
  shift 3
  local extra_env=("$@")
  # Drop host-detection vars from the calling environment (this test itself
  # may run under Grok/Copilot/Codex) so the default case is Claude unless
  # extra_env puts them back.
  (cd "$work" && env -u GROK_SESSION_ID -u COPILOT_CLI -u PLUGIN_ROOT \
    "${extra_env[@]}" HOME="$home" CODEXBAR_QUOTA_FLAG_PATH="$flag_path" "$SCRIPT")
}

# Each case: provider label and extra env assignments (as an array, one
# NAME=value per element) to simulate that tool's own hook runner. Claude
# Code sets neither GROK_SESSION_ID nor a bare PLUGIN_ROOT, so it's exercised
# as the "no extra env" default case (an empty array). Copilot CLI exports a
# bare PLUGIN_ROOT to plugin hooks as well (it accepts both the
# ${CLAUDE_PLUGIN_ROOT} and ${PLUGIN_ROOT} placeholders), so that case
# carries both variables: COPILOT_CLI must win, or Copilot claims the Codex
# flag.
run_case() {
  local provider="$1"
  shift
  local extra_env=("$@")
  local flag_path="$TMP_DIR/$provider/quota-low.json"
  mkdir -p "$(dirname "$flag_path")"

  # --- no flag file present: must be a silent no-op (exit 0) ---
  local rc=0
  run_reminder "$EMPTY_HOME" "$WORK_DIR" "$flag_path" "${extra_env[@]}" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "[$provider] expected exit 0 with no flag file, got $rc"

  # --- flag file present: must fire (exit 2), mention window/percent/reset
  #     and the wrap-up procedure, name the cwd dest, then clear the flag ---
  printf '%s' "$FIXTURE" >"$flag_path"

  rc=0
  local stderr_output
  stderr_output="$(run_reminder "$EMPTY_HOME" "$WORK_DIR" "$flag_path" "${extra_env[@]}" \
    2>&1 1>/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || fail "[$provider] expected exit 2 with a flag file present, got $rc"

  assert_procedure "$stderr_output" "$provider"

  local expected_dest="$WORK_DIR/$TODAY-quota-handoff.md"
  case "$stderr_output" in
    *"$expected_dest"*) ;;
    *) fail "[$provider] reminder does not mention cwd dest $expected_dest (got: $stderr_output)" ;;
  esac
  case "$stderr_output" in
    *"never a temp dir"*) ;;
    *) fail "[$provider] cwd dest should say never a temp dir (got: $stderr_output)" ;;
  esac

  [ ! -f "$flag_path" ] || fail "[$provider] flag file was not cleared after firing"

  # --- a second run with the flag gone must go back to being a no-op ---
  rc=0
  run_reminder "$EMPTY_HOME" "$WORK_DIR" "$flag_path" "${extra_env[@]}" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "[$provider] expected exit 0 after the flag was already cleared, got $rc"
}

run_case "claude"
run_case "grok" "GROK_SESSION_ID=test-session"
run_case "codex" "PLUGIN_ROOT=/tmp/fake-codex-plugin-root"
run_case "copilot" "COPILOT_CLI=1" "PLUGIN_ROOT=/tmp/fake-copilot-plugin-root"

# --- to-memory present, cwd is not a git repo: global short-term path ---
MEM_HOME="$TMP_DIR/mem-home"
mkdir -p "$MEM_HOME/.agents/skills/to-memory"
printf '# to-memory\n' >"$MEM_HOME/.agents/skills/to-memory/SKILL.md"
MEM_FLAG="$TMP_DIR/mem/quota-low.json"
mkdir -p "$(dirname "$MEM_FLAG")"
printf '%s' "$FIXTURE" >"$MEM_FLAG"
RC=0
MEM_STDERR="$(run_reminder "$MEM_HOME" "$WORK_DIR" "$MEM_FLAG" 2>&1 1>/dev/null)" || RC=$?
[ "$RC" -eq 2 ] || fail "to-memory without git: expected exit 2, got $RC"
assert_procedure "$MEM_STDERR" "to-memory-global"
GLOBAL_DEST="$MEM_HOME/.agents/memories/$TODAY-handoff-<topic>.md"
case "$MEM_STDERR" in
  *"$GLOBAL_DEST"*) ;;
  *) fail "to-memory without git: expected dest $GLOBAL_DEST (got: $MEM_STDERR)" ;;
esac
case "$MEM_STDERR" in
  *"never a temp dir"*) fail "to-memory dest should not say never a temp dir (got: $MEM_STDERR)" ;;
esac
[ ! -d "$MEM_HOME/.agents/memories" ] \
  || fail "hook must not create the global memories directory"

# --- to-memory present, cwd is a git repo, proj-memory-path.sh works ---
GIT_HOME="$TMP_DIR/git-home"
GIT_WORK="$TMP_DIR/git-work"
mkdir -p "$GIT_HOME/.agents/skills/to-memory/scripts" "$GIT_WORK"
printf '# to-memory\n' >"$GIT_HOME/.agents/skills/to-memory/SKILL.md"
cp "$PROJ_MEMORY_PATH" "$GIT_HOME/.agents/skills/to-memory/scripts/proj-memory-path.sh"
chmod +x "$GIT_HOME/.agents/skills/to-memory/scripts/proj-memory-path.sh"
git -C "$GIT_WORK" init -b main >/dev/null
EXPECTED_PROJ_DIR="$(HOME="$GIT_HOME" "$GIT_HOME/.agents/skills/to-memory/scripts/proj-memory-path.sh" "$GIT_WORK")"
[ ! -d "$EXPECTED_PROJ_DIR" ] || fail "resolver without --ensure should not create $EXPECTED_PROJ_DIR"
GIT_FLAG="$TMP_DIR/git/quota-low.json"
mkdir -p "$(dirname "$GIT_FLAG")"
printf '%s' "$FIXTURE" >"$GIT_FLAG"
RC=0
GIT_STDERR="$(run_reminder "$GIT_HOME" "$GIT_WORK" "$GIT_FLAG" 2>&1 1>/dev/null)" || RC=$?
[ "$RC" -eq 2 ] || fail "to-memory git: expected exit 2, got $RC"
assert_procedure "$GIT_STDERR" "to-memory-git"
PROJ_DEST="$EXPECTED_PROJ_DIR/$TODAY-handoff-<topic>.md"
case "$GIT_STDERR" in
  *"$PROJ_DEST"*) ;;
  *) fail "to-memory git: expected dest $PROJ_DEST (got: $GIT_STDERR)" ;;
esac
[ ! -d "$EXPECTED_PROJ_DIR" ] \
  || fail "hook must not create the project memory directory ($EXPECTED_PROJ_DIR)"

# --- to-memory present, git repo, but proj-memory-path.sh missing: global ---
NOSCRIPT_HOME="$TMP_DIR/noscript-home"
NOSCRIPT_WORK="$TMP_DIR/noscript-work"
mkdir -p "$NOSCRIPT_HOME/.agents/skills/to-memory" "$NOSCRIPT_WORK"
printf '# to-memory\n' >"$NOSCRIPT_HOME/.agents/skills/to-memory/SKILL.md"
git -C "$NOSCRIPT_WORK" init -b main >/dev/null
NOSCRIPT_FLAG="$TMP_DIR/noscript/quota-low.json"
mkdir -p "$(dirname "$NOSCRIPT_FLAG")"
printf '%s' "$FIXTURE" >"$NOSCRIPT_FLAG"
RC=0
NOSCRIPT_STDERR="$(run_reminder "$NOSCRIPT_HOME" "$NOSCRIPT_WORK" "$NOSCRIPT_FLAG" \
  2>&1 1>/dev/null)" || RC=$?
[ "$RC" -eq 2 ] || fail "to-memory git without script: expected exit 2, got $RC"
NOSCRIPT_DEST="$NOSCRIPT_HOME/.agents/memories/$TODAY-handoff-<topic>.md"
case "$NOSCRIPT_STDERR" in
  *"$NOSCRIPT_DEST"*) ;;
  *) fail "to-memory git without script: expected dest $NOSCRIPT_DEST (got: $NOSCRIPT_STDERR)" ;;
esac

# --- to-memory present, git repo, proj-memory-path.sh exits 1: global ---
FAIL_HOME="$TMP_DIR/fail-home"
FAIL_WORK="$TMP_DIR/fail-work"
mkdir -p "$FAIL_HOME/.agents/skills/to-memory/scripts" "$FAIL_WORK"
printf '# to-memory\n' >"$FAIL_HOME/.agents/skills/to-memory/SKILL.md"
printf '#!/usr/bin/env bash\nexit 1\n' \
  >"$FAIL_HOME/.agents/skills/to-memory/scripts/proj-memory-path.sh"
chmod +x "$FAIL_HOME/.agents/skills/to-memory/scripts/proj-memory-path.sh"
git -C "$FAIL_WORK" init -b main >/dev/null
FAIL_FLAG="$TMP_DIR/fail/quota-low.json"
mkdir -p "$(dirname "$FAIL_FLAG")"
printf '%s' "$FIXTURE" >"$FAIL_FLAG"
RC=0
FAIL_STDERR="$(run_reminder "$FAIL_HOME" "$FAIL_WORK" "$FAIL_FLAG" 2>&1 1>/dev/null)" || RC=$?
[ "$RC" -eq 2 ] || fail "to-memory git with failing script: expected exit 2, got $RC"
FAIL_DEST="$FAIL_HOME/.agents/memories/$TODAY-handoff-<topic>.md"
case "$FAIL_STDERR" in
  *"$FAIL_DEST"*) ;;
  *) fail "to-memory git with failing script: expected dest $FAIL_DEST (got: $FAIL_STDERR)" ;;
esac

# A relative XDG value is invalid by spec; runtime hooks fall back safely.
FALLBACK_HOME="$TMP_DIR/fallback-home"
mkdir -p "$FALLBACK_HOME/.local/state/codexbar-quota-handoff"
printf '%s' "$FIXTURE" >"$FALLBACK_HOME/.local/state/codexbar-quota-handoff/quota-low-claude.json"
RC=0
(cd "$WORK_DIR" && env -u GROK_SESSION_ID -u COPILOT_CLI -u PLUGIN_ROOT \
  HOME="$FALLBACK_HOME" XDG_STATE_HOME=relative "$SCRIPT" >/dev/null 2>&1) || RC=$?
[ "$RC" -eq 2 ] || fail "relative XDG_STATE_HOME should fall back to HOME, got exit $RC"

# --- concurrent invocations against the same flag (simulating PostToolUse
#     firing for two tool calls in the same parallel batch): the atomic mv
#     claim must guarantee exactly one winner (exit 2, prints once) and one
#     loser (exit 0, silent) — not two duplicate reminders. This holds
#     regardless of scheduling, since only one process's rename of the same
#     source path can ever succeed. ---
CONCURRENT_FLAG="$TMP_DIR/concurrent/quota-low.json"
mkdir -p "$(dirname "$CONCURRENT_FLAG")"
printf '%s' "$FIXTURE" >"$CONCURRENT_FLAG"

RC_A_FILE="$TMP_DIR/rc-a"
RC_B_FILE="$TMP_DIR/rc-b"
(
  rc=0
  run_reminder "$EMPTY_HOME" "$WORK_DIR" "$CONCURRENT_FLAG" >/dev/null 2>&1 || rc=$?
  echo "$rc" >"$RC_A_FILE"
) &
(
  rc=0
  run_reminder "$EMPTY_HOME" "$WORK_DIR" "$CONCURRENT_FLAG" >/dev/null 2>&1 || rc=$?
  echo "$rc" >"$RC_B_FILE"
) &
wait

COMBINED_RCS="$(cat "$RC_A_FILE" "$RC_B_FILE" | sort | paste -sd, -)"
[ "$COMBINED_RCS" = "0,2" ] \
  || fail "expected exactly one concurrent invocation to win (exit 2) and one to lose (exit 0), got: $COMBINED_RCS"

[ ! -f "$CONCURRENT_FLAG" ] || fail "flag file leaked after concurrent invocations"
LEFTOVER_CLAIMS="$(find "$(dirname "$CONCURRENT_FLAG")" -name '*.claimed.*' | wc -l | tr -d ' ')"
[ "$LEFTOVER_CLAIMS" -eq 0 ] || fail "a claimed temp file was left behind after concurrent invocations"

# --- a flag whose resetAt is already in the past (stale, e.g. left unclaimed
#     across a long idle gap) must be discarded silently, not relayed ---
STALE_FLAG="$TMP_DIR/stale/quota-low.json"
mkdir -p "$(dirname "$STALE_FLAG")"
printf '{"event":"quota_low","provider":"claude","resetAt":"%s","timestamp":"2026-08-12T15:32:00Z","usagePercent":1.0,"window":"session"}' \
  "$PAST_RESET_AT" >"$STALE_FLAG"

RC=0
run_reminder "$EMPTY_HOME" "$WORK_DIR" "$STALE_FLAG" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "expected exit 0 for a flag with a past resetAt, got $RC"
[ ! -f "$STALE_FLAG" ] || fail "stale flag file was not cleared"

# --- an unparsable resetAt must fail open (still relay the reminder) ---
UNPARSABLE_FLAG="$TMP_DIR/unparsable/quota-low.json"
mkdir -p "$(dirname "$UNPARSABLE_FLAG")"
printf '{"event":"quota_low","provider":"claude","resetAt":"not-a-date","timestamp":"2026-08-12T15:32:00Z","usagePercent":0.93,"window":"session"}' \
  >"$UNPARSABLE_FLAG"

RC=0
UNPARSABLE_STDERR="$(run_reminder "$EMPTY_HOME" "$WORK_DIR" "$UNPARSABLE_FLAG" \
  2>&1 1>/dev/null)" || RC=$?
[ "$RC" -eq 2 ] || fail "expected exit 2 (fail open) for an unparsable resetAt, got $RC"
assert_procedure "$UNPARSABLE_STDERR" "unparsable"

echo "codexbar-quota-handoff quota-reminder checks passed"
