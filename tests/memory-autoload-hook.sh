#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/memory-autoload"
LOADER="$PLUGIN_DIR/hooks/load-memory.sh"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
MARKET_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKET_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"

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

# --- plugin.json + hooks.json: valid JSON and correct wiring ---
for f in "$PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$HOOKS_JSON"; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" || fail "invalid JSON: $f"
done

python3 - "$HOOKS_JSON" <<'PY' || fail "hooks.json SessionStart wiring incorrect"
import json, sys
d = json.load(open(sys.argv[1]))
entries = d["hooks"]["SessionStart"]
cmds = [h["command"] for e in entries for h in e["hooks"]]
assert cmds == ['bash "${CLAUDE_PLUGIN_ROOT}/hooks/load-memory.sh"'], "session start should only load memory"
PY

# --- marketplace.json: valid JSON and lists the plugin ---
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MARKET_JSON" || fail "invalid JSON: $MARKET_JSON"

python3 - "$MARKET_JSON" <<'PY' || fail "marketplace.json does not list memory-autoload"
import json, sys
d = json.load(open(sys.argv[1]))
plugins = d["plugins"]
assert any(
    p["name"] == "memory-autoload" and p["source"] == "./plugins/memory-autoload"
    for p in plugins
), "memory-autoload entry missing or wrong source"
PY

# --- Codex plugin.json + marketplace.json: valid JSON and correct metadata ---
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$CODEX_MARKET_JSON" || fail "invalid JSON: $CODEX_MARKET_JSON"

python3 - "$CODEX_PLUGIN_JSON" <<'PY' || fail "Codex plugin.json metadata incorrect"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["name"] == "memory-autoload", "wrong plugin name"
assert d["version"] == "0.1.1", "wrong plugin version"
assert "memory" in d["description"].lower(), "description should mention memory"
assert d["author"]["name"] == "Charley Wu", "wrong author"
assert d["repository"] == "https://github.com/akunzai/agent-skills", "wrong repository"
assert d["license"] == "MIT", "wrong license"
assert d["interface"]["displayName"] == "Memory Autoload", "wrong displayName"
assert d["interface"]["longDescription"] == "Loads ~/.agents/MEMORY.md into context at session start.", "wrong longDescription"
assert d["interface"]["category"] == "Productivity", "wrong category"
assert d["interface"]["defaultPrompt"] == "Use Memory Autoload to load durable memory at session start.", "wrong defaultPrompt"
assert "hooks" not in d, "default hooks/hooks.json does not need a manifest hooks field"
PY

python3 - "$CODEX_MARKET_JSON" <<'PY' || fail "Codex marketplace.json does not list memory-autoload"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["name"] == "akunzai", "wrong marketplace name"
assert d["interface"]["displayName"] == "akunzai-agent-skills", "wrong marketplace displayName"
plugins = d["plugins"]
entry = next((p for p in plugins if p["name"] == "memory-autoload"), None)
assert entry is not None, "memory-autoload entry missing"
assert entry["source"] == {
    "source": "local",
    "path": "./plugins/memory-autoload",
}, "wrong Codex marketplace source"
assert entry["policy"] == {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL",
}, "wrong Codex marketplace policy"
assert entry["category"] == "Productivity", "wrong Codex marketplace category"
PY

echo "memory-autoload hook checks passed"
