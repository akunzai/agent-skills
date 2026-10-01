#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-codex-agents.sh

Install this plugin's Codex CLI development-worker definitions into the
personal Codex agents directory (~/.codex/agents/). Unmodified released
definitions are upgraded; edited or unknown files are preserved as conflicts.

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
agents=(repo-explorer.toml evidence-collector.toml log-summarizer.toml)
mkdir -p "$dest"
for name in "${agents[@]}"; do
  source="$plugin_root/codex-agents/$name"
  target="$dest/$name"
  if [[ -e "$target" ]] && ! cmp -s "$source" "$target"; then
    # Byte equality with a known release proves this is safe to upgrade.
    # A plugin install is a snapshot, so do not depend on Git history here.
    if [[ -f "$target" ]]; then
      # Git Bash on Windows ships sha256sum but not shasum.
      if command -v shasum >/dev/null 2>&1; then
        digest="$(shasum -a 256 "$target" | cut -d' ' -f1)"
      else
        digest="$(sha256sum "$target" | cut -d' ' -f1)"
      fi
      if grep -Fqx "$name $digest" "$plugin_root/scripts/released-codex-agents.sha256"; then
        continue
      fi
    fi
    echo "Refusing to overwrite modified or unknown agent: $target" >&2
    echo "Back up this file outside ~/.codex/agents/ before retrying if you want the plugin definition." >&2
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

bash "$plugin_root/scripts/retired-codex-agents.sh" "$dest" || true

echo "Done. Start a new Codex CLI session to pick up the new agents."
