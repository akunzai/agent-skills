#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-codex-agents.sh

Install this plugin's four Codex CLI development-worker definitions into the
personal Codex agents directory (~/.codex/agents/). Existing files that differ
from the plugin definitions are preserved and reported as conflicts.

Options:
  -h, --help  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

dest="$HOME/.codex/agents"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agents=(repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml)
mkdir -p "$dest"
for name in "${agents[@]}"; do
  source="$plugin_root/codex-agents/$name"
  target="$dest/$name"
  if [[ -e "$target" ]] && ! cmp -s "$source" "$target"; then
    echo "Refusing to overwrite non-plugin agent: $target" >&2
    exit 73
  fi
done
for name in "${agents[@]}"; do
  source="$plugin_root/codex-agents/$name"
  target="$dest/$name"
  temporary="$(mktemp "$dest/.${name}.XXXXXX")"
  cp "$source" "$temporary"
  chmod 644 "$temporary"
  mv "$temporary" "$target"
  echo "  installed $name -> $target"
done

echo "Done. Start a new Codex CLI session to pick up the new agents."
