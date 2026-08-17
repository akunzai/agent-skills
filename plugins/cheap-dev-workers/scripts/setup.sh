#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup.sh

Install this plugin's four Codex CLI development-worker definitions
into the personal Codex agents directory (~/.codex/agents/). Codex CLI has no
plugin-bundled agent mechanism today (it only reads ~/.codex/agents/ or a
trusted project's .codex/agents/), so `codex plugin add` alone will not
register them -- this script is the actual install step for the Codex side
of this plugin. The Claude Code side needs no setup: its agents/ directory
is auto-discovered once the plugin is installed.

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

cat <<EOF

== Plugin marketplaces ==
Run these if using the Codex plugin manager for updates (not required for
the agents above -- this script is the actual install step for those).

  codex plugin marketplace add akunzai/agent-skills
  codex plugin add cheap-dev-workers --marketplace akunzai-agent-skills

Done. Start a new Codex CLI session to pick up the new agents.
EOF
