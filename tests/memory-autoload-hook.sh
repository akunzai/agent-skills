#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/memory-autoload"
LOADER="$PLUGIN_DIR/hooks/load-memory.sh"

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

echo "memory-autoload hook checks passed"
