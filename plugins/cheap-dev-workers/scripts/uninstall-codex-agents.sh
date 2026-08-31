#!/usr/bin/env bash
set -euo pipefail

dest="$HOME/.codex/agents"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agents=(repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml)
removed=false

for name in "${agents[@]}"; do
  target="$dest/$name"
  if [[ -f "$target" ]]; then
    source="$plugin_root/codex-agents/$name"
    if ! cmp -s "$source" "$target"; then
      echo "Refusing to remove modified or independently installed agent: $target" >&2
      exit 73
    fi
  fi
done

for name in "${agents[@]}"; do
  target="$dest/$name"
  if [[ -f "$target" ]]; then
    rm -f "$target"
    echo "  removed $target"
    removed=true
  fi
done

if [[ "$removed" == false ]]; then
  echo "  no cheap-dev-workers Codex personal agents found in $dest"
fi
