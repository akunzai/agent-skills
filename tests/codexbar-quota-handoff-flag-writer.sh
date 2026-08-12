#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/codexbar-quota-handoff/scripts/codexbar-quota-flag.sh"

fail() {
  echo "codexbar-quota-handoff flag-writer check failed: $*" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- requires a provider argument ---
RC=0
printf '{}' | "$SCRIPT" >/dev/null 2>&1 || RC=$?
[ "$RC" -ne 0 ] || fail "expected a non-zero exit with no provider argument"

# --- each provider writes to its own path, from the same CodexBar hook rule
#     pattern (one rule per provider, all calling this same script) ---
for provider in claude grok codex; do
  FIXTURE="{\"account\":null,\"event\":\"quota_low\",\"limit\":null,\"provider\":\"$provider\",\"resetAt\":\"2026-08-13T02:00:00Z\",\"status\":null,\"timestamp\":\"2026-08-12T15:32:00Z\",\"usagePercent\":0.93,\"used\":null,\"window\":\"session\"}"
  FLAG_PATH="$TMP_DIR/$provider/quota-low.json"

  printf '%s' "$FIXTURE" | CODEXBAR_QUOTA_FLAG_PATH="$FLAG_PATH" "$SCRIPT" "$provider"

  [ -f "$FLAG_PATH" ] || fail "[$provider] flag file was not created at $FLAG_PATH"

  ACTUAL="$(cat "$FLAG_PATH")"
  [ "$ACTUAL" = "$FIXTURE" ] || fail "[$provider] flag file content does not match the stdin payload verbatim"

  jq empty "$FLAG_PATH" 2>/dev/null || fail "[$provider] flag file is not valid JSON"
done

# --- overwrites an existing flag file rather than erroring or appending ---
FIXTURE2='{"event":"quota_low","provider":"claude","resetAt":"2026-08-20T02:00:00Z","timestamp":"2026-08-13T09:00:00Z","usagePercent":0.91,"window":"weekly"}'
FLAG_PATH="$TMP_DIR/claude/quota-low.json"
printf '%s' "$FIXTURE2" | CODEXBAR_QUOTA_FLAG_PATH="$FLAG_PATH" "$SCRIPT" claude
ACTUAL2="$(cat "$FLAG_PATH")"
[ "$ACTUAL2" = "$FIXTURE2" ] || fail "flag file was not overwritten with the newer payload"

# --- without an env override, the XDG state fallback is keyed by provider, so
#     concurrent providers can never collide on the same flag file ---
FAKE_HOME="$TMP_DIR/home"
mkdir -p "$FAKE_HOME"
env -u CODEXBAR_QUOTA_FLAG_PATH -u XDG_STATE_HOME HOME="$FAKE_HOME" bash -c "printf '{}' | '$SCRIPT' claude"
env -u CODEXBAR_QUOTA_FLAG_PATH -u XDG_STATE_HOME HOME="$FAKE_HOME" bash -c "printf '{}' | '$SCRIPT' grok"

[ -f "$FAKE_HOME/.local/state/codexbar-quota-handoff/quota-low-claude.json" ] \
  || fail "default claude flag path was not written under \$HOME"
[ -f "$FAKE_HOME/.local/state/codexbar-quota-handoff/quota-low-grok.json" ] \
  || fail "default grok flag path was not written under \$HOME"

XDG_STATE="$TMP_DIR/custom-state"
printf '{}' | XDG_STATE_HOME="$XDG_STATE" "$SCRIPT" codex
[ -f "$XDG_STATE/codexbar-quota-handoff/quota-low-codex.json" ] \
  || fail "custom XDG_STATE_HOME was not honored"

# CodexBar can pass the setup-resolved state directory explicitly because a
# macOS GUI process may not inherit the terminal's XDG environment.
EXPLICIT_STATE="$TMP_DIR/explicit-state"
printf '{}' | "$SCRIPT" grok "$EXPLICIT_STATE"
[ -f "$EXPLICIT_STATE/quota-low-grok.json" ] \
  || fail "explicit state directory argument was not honored"

echo "codexbar-quota-handoff flag-writer checks passed"
