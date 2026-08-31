#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: upgrade.sh [options]

Check and upgrade the cheap-dev-workers plugin for Claude Code, Codex CLI,
and GitHub Copilot CLI.

Options:
  --check            Check current installed versions against available version without upgrading
  --claude-only      Only inspect/upgrade Claude Code plugin
  --codex-only       Only inspect/upgrade Codex CLI plugin and personal agents
  --copilot-only     Only inspect/upgrade GitHub Copilot CLI plugin
  --scope <scope>    Claude Code plugin scope: 'user' (default) or 'project'
  --force            Force overwriting modified Codex agent definitions in ~/.codex/agents/
  -h, --help         Show this help
EOF
}

check_only=false
target_platform="all"
scope="user"
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --check)
      check_only=true
      shift
      ;;
    --claude-only)
      target_platform="claude"
      shift
      ;;
    --codex-only)
      target_platform="codex"
      shift
      ;;
    --copilot-only)
      target_platform="copilot"
      shift
      ;;
    --scope)
      scope="${2:?--scope requires a value (user|project)}"
      shift 2
      ;;
    --scope=*)
      scope="${1#--scope=}"
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ "$scope" != "user" && "$scope" != "project" ]]; then
  echo "ERROR: Invalid scope '$scope'. Must be 'user' or 'project'." >&2
  exit 1
fi

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_json="$plugin_root/.claude-plugin/plugin.json"
plugin_version="$(jq -r '.version // "unknown"' "$claude_json" 2>/dev/null || echo "unknown")"
agents=(repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml)
codex_dest="${HOME}/.codex/agents"

echo "== cheap-dev-workers (Repository version: $plugin_version) =="

# ---------------- Claude Code ----------------
upgrade_claude() {
  echo ""
  echo "== Claude Code =="
  if ! command -v claude >/dev/null 2>&1; then
    echo "  Claude CLI not found on PATH; skipping Claude Code."
    return 0
  fi

  local plugin_list installed_version
  plugin_list="$(claude plugin list 2>/dev/null || true)"
  installed_version="$(printf '%s\n' "$plugin_list" | awk '/cheap-dev-workers@akunzai-agent-skills/{flag=1; next} flag && /Version:/{print $2; exit}')"

  if [[ -z "$installed_version" ]]; then
    echo "  cheap-dev-workers is not installed in Claude Code (scope: $scope)."
    if [[ "$check_only" == false ]]; then
      echo "  To install: claude plugin install cheap-dev-workers@akunzai-agent-skills --scope $scope"
    fi
    return 0
  fi

  echo "  Installed Claude plugin version: $installed_version"

  if [[ "$check_only" == true ]]; then
    if [[ "$installed_version" == "$plugin_version" ]]; then
      echo "  Claude plugin is up to date ($installed_version)."
    else
      echo "  Claude plugin can be upgraded ($installed_version -> $plugin_version)."
    fi
    return 0
  fi

  echo "  Updating marketplace akunzai-agent-skills..."
  claude plugin marketplace update akunzai-agent-skills 2>/dev/null || true

  echo "  Upgrading cheap-dev-workers plugin (scope: $scope)..."
  claude plugin update "cheap-dev-workers@akunzai-agent-skills" --scope "$scope"
}

# ---------------- Codex CLI ----------------
upgrade_codex() {
  echo ""
  echo "== Codex CLI =="
  if ! command -v codex >/dev/null 2>&1; then
    echo "  Codex CLI not found on PATH; skipping Codex CLI."
    return 0
  fi

  local codex_plugin_list installed_plugin_version
  codex_plugin_list="$(codex plugin list 2>/dev/null || true)"
  installed_plugin_version="$(printf '%s\n' "$codex_plugin_list" | awk '$1 ~ /^cheap-dev-workers/ { for (i=2; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+(\.[0-9]+)?$/) { print $i; exit } }')"

  if [[ -n "$installed_plugin_version" ]]; then
    echo "  Installed Codex plugin version: $installed_plugin_version"
  else
    echo "  cheap-dev-workers is not registered in Codex plugin manager (or using personal agents only)."
  fi

  # Check personal agents in ~/.codex/agents/
  local all_match=true
  local missing=false
  for name in "${agents[@]}"; do
    local src="$plugin_root/codex-agents/$name"
    local tgt="$codex_dest/$name"
    if [[ ! -f "$tgt" ]]; then
      missing=true
      all_match=false
    elif ! cmp -s "$src" "$tgt"; then
      all_match=false
    fi
  done

  if [[ "$check_only" == true ]]; then
    if [[ "$all_match" == true ]]; then
      echo "  Codex personal agents in $codex_dest are up to date ($plugin_version)."
    elif [[ "$missing" == true ]]; then
      echo "  Some Codex personal agents are missing in $codex_dest."
    else
      echo "  Codex personal agents in $codex_dest differ from repository ($plugin_version)."
    fi
    return 0
  fi

  # Upgrade Codex marketplace snapshot if available
  if codex plugin marketplace list 2>/dev/null | grep -q 'akunzai-agent-skills'; then
    echo "  Upgrading Codex marketplace snapshot akunzai-agent-skills..."
    codex plugin marketplace upgrade akunzai-agent-skills 2>/dev/null || true
  fi

  # Update personal agent definitions
  echo "  Updating Codex personal agents in $codex_dest..."
  mkdir -p "$codex_dest"

  for name in "${agents[@]}"; do
    local src="$plugin_root/codex-agents/$name"
    local tgt="$codex_dest/$name"
    if [[ -e "$tgt" ]] && ! cmp -s "$src" "$tgt" && [[ "$force" == false ]]; then
      echo "  Overwriting existing agent: $name -> $tgt"
    fi
    local temporary
    temporary="$(mktemp "$codex_dest/.${name}.XXXXXX")"
    cp "$src" "$temporary"
    chmod 644 "$temporary"
    mv "$temporary" "$tgt"
    echo "  updated $name -> $tgt"
  done
}

# ---------------- GitHub Copilot CLI ----------------
# Copilot installs this plugin straight from the .claude-plugin manifests, so
# there are no Copilot-specific files to copy — only the plugin manager to
# nudge. Its `plugin list` prints one line per plugin, e.g.
#   • cheap-dev-workers@akunzai-agent-skills (v1.2.1) (enabled)
upgrade_copilot() {
  echo ""
  echo "== GitHub Copilot CLI =="
  if ! command -v copilot >/dev/null 2>&1; then
    echo "  Copilot CLI not found on PATH; skipping GitHub Copilot CLI."
    return 0
  fi

  local plugin_list installed_version
  plugin_list="$(copilot plugin list 2>/dev/null || true)"
  installed_version="$(printf '%s\n' "$plugin_list" \
    | sed -n 's/.*cheap-dev-workers@akunzai-agent-skills.*(v\([0-9][0-9.]*\)).*/\1/p' \
    | head -n 1)"

  if [[ -z "$installed_version" ]]; then
    echo "  cheap-dev-workers is not installed in Copilot CLI."
    if [[ "$check_only" == false ]]; then
      echo "  To install: copilot plugin install cheap-dev-workers@akunzai-agent-skills"
    fi
    return 0
  fi

  echo "  Installed Copilot plugin version: $installed_version"

  if [[ "$check_only" == true ]]; then
    if [[ "$installed_version" == "$plugin_version" ]]; then
      echo "  Copilot plugin is up to date ($installed_version)."
    else
      echo "  Copilot plugin can be upgraded ($installed_version -> $plugin_version)."
    fi
    return 0
  fi

  echo "  Updating marketplace akunzai-agent-skills..."
  copilot plugin marketplace update akunzai-agent-skills 2>/dev/null || true

  echo "  Upgrading cheap-dev-workers plugin..."
  copilot plugin update "cheap-dev-workers@akunzai-agent-skills"
}

if [[ "$target_platform" == "all" || "$target_platform" == "claude" ]]; then
  upgrade_claude
fi

if [[ "$target_platform" == "all" || "$target_platform" == "codex" ]]; then
  upgrade_codex
fi

if [[ "$target_platform" == "all" || "$target_platform" == "copilot" ]]; then
  upgrade_copilot
fi

echo ""
if [[ "$check_only" == true ]]; then
  echo "Version check complete."
else
  echo "Upgrade complete. Restart Claude Code / Codex / Copilot sessions to apply changes."
fi
