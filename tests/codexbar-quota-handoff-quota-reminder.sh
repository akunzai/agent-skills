#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/quota-reminder.sh"

fail() {
  echo "codexbar-quota-handoff quota-reminder check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

FIXTURE="{\"event\":\"quota_low\",\"provider\":\"claude\",\"resetAt\":\"$FUTURE_RESET_AT\",\"timestamp\":\"2026-08-12T15:32:00Z\",\"usagePercent\":0.93,\"window\":\"session\"}"

# Each case: provider label, extra env assignments (as an array, one
# NAME=value per element) to simulate that tool's own hook runner, and the
# handoff-command text the reminder must mention. Claude Code sets neither
# GROK_SESSION_ID nor a bare PLUGIN_ROOT, so it's exercised as the "no extra
# env" default case (an empty array).
run_case() {
  local provider="$1" expected_cmd="$2"
  shift 2
  local extra_env=("$@")
  local flag_path="$TMP_DIR/$provider/quota-low.json"
  mkdir -p "$(dirname "$flag_path")"

  # --- no flag file present: must be a silent no-op (exit 0) ---
  local rc=0
  env "${extra_env[@]}" CODEXBAR_QUOTA_FLAG_PATH="$flag_path" "$SCRIPT" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "[$provider] expected exit 0 with no flag file, got $rc"

  # --- flag file present: must fire (exit 2), mention window/percent/reset
  #     and the tool-appropriate handoff command, then clear the flag ---
  printf '%s' "$FIXTURE" >"$flag_path"

  rc=0
  local stderr_output
  stderr_output="$(env "${extra_env[@]}" CODEXBAR_QUOTA_FLAG_PATH="$flag_path" "$SCRIPT" 2>&1 1>/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || fail "[$provider] expected exit 2 with a flag file present, got $rc"

  case "$stderr_output" in
    *session*) ;;
    *) fail "[$provider] reminder text does not mention the window (got: $stderr_output)" ;;
  esac

  case "$stderr_output" in
    *93*) ;;
    *) fail "[$provider] reminder text does not mention the usage percentage (got: $stderr_output)" ;;
  esac

  case "$stderr_output" in
    *"$expected_cmd"*) ;;
    *) fail "[$provider] reminder text does not mention $expected_cmd (got: $stderr_output)" ;;
  esac

  [ ! -f "$flag_path" ] || fail "[$provider] flag file was not cleared after firing"

  # --- a second run with the flag gone must go back to being a no-op ---
  rc=0
  env "${extra_env[@]}" CODEXBAR_QUOTA_FLAG_PATH="$flag_path" "$SCRIPT" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "[$provider] expected exit 0 after the flag was already cleared, got $rc"
}

run_case "claude" "/handoff"
run_case "grok" "/handoff" "GROK_SESSION_ID=test-session"
# shellcheck disable=SC2016
run_case "codex" '$handoff' "PLUGIN_ROOT=/tmp/fake-codex-plugin-root"

# A relative XDG value is invalid by spec; runtime hooks fall back safely.
FALLBACK_HOME="$TMP_DIR/fallback-home"
mkdir -p "$FALLBACK_HOME/.local/state/codexbar-quota-handoff"
printf '%s' "$FIXTURE" >"$FALLBACK_HOME/.local/state/codexbar-quota-handoff/quota-low-claude.json"
RC=0
HOME="$FALLBACK_HOME" XDG_STATE_HOME=relative "$SCRIPT" >/dev/null 2>&1 || RC=$?
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
  CODEXBAR_QUOTA_FLAG_PATH="$CONCURRENT_FLAG" "$SCRIPT" >/dev/null 2>&1 || rc=$?
  echo "$rc" >"$RC_A_FILE"
) &
(
  rc=0
  CODEXBAR_QUOTA_FLAG_PATH="$CONCURRENT_FLAG" "$SCRIPT" >/dev/null 2>&1 || rc=$?
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
CODEXBAR_QUOTA_FLAG_PATH="$STALE_FLAG" "$SCRIPT" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "expected exit 0 for a flag with a past resetAt, got $RC"
[ ! -f "$STALE_FLAG" ] || fail "stale flag file was not cleared"

# --- an unparsable resetAt must fail open (still relay the reminder) ---
UNPARSABLE_FLAG="$TMP_DIR/unparsable/quota-low.json"
mkdir -p "$(dirname "$UNPARSABLE_FLAG")"
printf '{"event":"quota_low","provider":"claude","resetAt":"not-a-date","timestamp":"2026-08-12T15:32:00Z","usagePercent":0.93,"window":"session"}' \
  >"$UNPARSABLE_FLAG"

RC=0
CODEXBAR_QUOTA_FLAG_PATH="$UNPARSABLE_FLAG" "$SCRIPT" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || fail "expected exit 2 (fail open) for an unparsable resetAt, got $RC"

echo "codexbar-quota-handoff quota-reminder checks passed"
