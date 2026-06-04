#!/usr/bin/env bash
set -euo pipefail

memory_file="${MEMORY_FILE:-$HOME/.agents/MEMORY.md}"

if [ -r "$memory_file" ] && [ -s "$memory_file" ]; then
  echo "# Long-term memory (~/.agents/MEMORY.md) — durable cross-project instructions; apply before responding."
  cat "$memory_file" || true
fi

exit 0
