#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/memory-autoload"
LOADER="$PLUGIN_DIR/hooks/load-memory.sh"
NUDGE="$PLUGIN_DIR/hooks/nudge-memory-skills.sh"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"

fail() {
  echo "memory-autoload hook check failed: $*" >&2
  exit 1
}

# --- loader: present file ---
tmp="$(mktemp)"
printf 'KNOWN-MEMORY-LINE\n' > "$tmp"
out="$(MEMORY_FILE="$tmp" bash "$LOADER")"
rm -f "$tmp"
printf '%s' "$out" | grep -q 'Long-term memory' || fail "loader did not emit header"
printf '%s' "$out" | grep -q 'KNOWN-MEMORY-LINE' || fail "loader did not emit memory contents"

# --- loader: absent file ---
out="$(MEMORY_FILE="$ROOT_DIR/nonexistent-memory-file" bash "$LOADER")"
[ -z "$out" ] || fail "loader emitted output for absent file"

# --- nudge: names both skills ---
out="$(bash "$NUDGE")"
printf '%s' "$out" | grep -q 'mem-sync' || fail "nudge missing mem-sync"
printf '%s' "$out" | grep -q 'mem-auto' || fail "nudge missing mem-auto"

# --- plugin.json + hooks.json: valid JSON and correct wiring ---
for f in "$PLUGIN_JSON" "$HOOKS_JSON"; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" || fail "invalid JSON: $f"
done

python3 - "$HOOKS_JSON" <<'PY' || fail "hooks.json SessionStart wiring incorrect"
import json, sys
d = json.load(open(sys.argv[1]))
entries = d["hooks"]["SessionStart"]
cmds = [h["command"] for e in entries for h in e["hooks"]]
assert any("load-memory.sh" in c for c in cmds), "missing load-memory.sh"
assert any("nudge-memory-skills.sh" in c for c in cmds), "missing nudge-memory-skills.sh"
PY

echo "memory-autoload hook checks passed"
