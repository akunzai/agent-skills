#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: uninstall.sh

Remove this plugin's four Codex CLI development-worker definitions
from the personal Codex agents directory (~/.codex/agents/). Plugin-manager
removal commands are printed but not executed.

Options:
  -h, --help    Show this help
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
  echo "  nothing installed at $dest"
fi

cat <<'EOF'

== Plugin marketplaces ==
Run these commands if the Claude Code or Codex plugins were installed.

  claude plugin uninstall cheap-dev-workers@akunzai-agent-skills --scope user
  codex plugin remove cheap-dev-workers --marketplace akunzai-agent-skills

Done.
EOF
