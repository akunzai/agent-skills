#!/usr/bin/env bash
set -euo pipefail

# ensure-proj-memory-path.sh
# Ensures global project memory directory exists (runs migration if needed) and outputs path.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$PWD}"

GLOBAL_MEM_DIR="$("$SCRIPT_DIR/resolve-proj-memory-path.sh" "$TARGET_DIR")"
"$SCRIPT_DIR/migrate-legacy-proj-memory.sh" "$TARGET_DIR"
mkdir -p "$GLOBAL_MEM_DIR"

echo "$GLOBAL_MEM_DIR"
