#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"
CLAUDE_PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
CLAUDE_MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$ROOT_DIR/.agents/plugins/marketplace.json"

fail() {
  echo "cheap-dev-workers manifest check failed: $*" >&2
  exit 1
}

for f in "$CLAUDE_PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$CLAUDE_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON"; do
  [ -f "$f" ] || fail "$f is missing"
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
done

CLAUDE_NAME="$(jq -r '.name' "$CLAUDE_PLUGIN_JSON")"
[ "$CLAUDE_NAME" = "cheap-dev-workers" ] || fail "unexpected Claude manifest name: $CLAUDE_NAME"

CODEX_NAME="$(jq -r '.name' "$CODEX_PLUGIN_JSON")"
[ "$CODEX_NAME" = "cheap-dev-workers" ] || fail "unexpected Codex manifest name: $CODEX_NAME"

# --- marketplace.json must actually list this plugin ---
CLAUDE_MARKETPLACE_ENTRY="$(jq -r '.plugins[] | select(.name == "cheap-dev-workers") | .source' "$CLAUDE_MARKETPLACE_JSON")"
[ "$CLAUDE_MARKETPLACE_ENTRY" = "./plugins/cheap-dev-workers" ] || fail "Claude marketplace entry is missing"

CODEX_MARKETPLACE_PATH="$(jq -r '.plugins[] | select(.name == "cheap-dev-workers") | .source.path' "$CODEX_MARKETPLACE_JSON")"
[ "$CODEX_MARKETPLACE_PATH" = "./plugins/cheap-dev-workers" ] || fail "Codex marketplace entry is missing"

grep -q 'plugins/cheap-dev-workers/README.md' "$ROOT_DIR/README.md" \
  || fail "root README is missing the cheap-dev-workers plugin"
# --- Claude Code agents auto-discovered from agents/ ---
for agent in repo-explorer check-runner log-summarizer commit-writer; do
  [ -f "$PLUGIN_DIR/agents/$agent.md" ] || fail "agents/$agent.md is missing"
  [ -f "$PLUGIN_DIR/codex-agents/$agent.toml" ] || fail "codex-agents/$agent.toml is missing"
done
[ ! -e "$PLUGIN_DIR/agents/verifier.md" ] || fail "legacy Claude verifier still ships"
[ ! -e "$PLUGIN_DIR/codex-agents/verifier.toml" ] || fail "legacy Codex verifier still ships"

# --- plugin-local scripts are internal helpers, not lifecycle entry points ---
for script in install-codex-agents.sh uninstall-codex-agents.sh sanitize-log.sh; do
  path="$PLUGIN_DIR/scripts/$script"
  [ -f "$path" ] || fail "scripts/$script is missing"
  [ -x "$path" ] || fail "scripts/$script is not executable"
done

# --- CLAUDE.md must be the symlink-to-AGENTS.md convention ---
[ -L "$PLUGIN_DIR/CLAUDE.md" ] || fail "CLAUDE.md must be a symlink to AGENTS.md"
CLAUDE_MD_TARGET="$(readlink "$PLUGIN_DIR/CLAUDE.md")"
[ "$CLAUDE_MD_TARGET" = "AGENTS.md" ] || fail "CLAUDE.md symlink target is '$CLAUDE_MD_TARGET', expected 'AGENTS.md'"

echo "cheap-dev-workers manifest checks passed"
