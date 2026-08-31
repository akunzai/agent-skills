#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
if [[ -z "$action" ]]; then
  echo "Usage: manage-plugins.sh <install|upgrade|uninstall> [options]" >&2
  exit 64
fi
shift

case "$action" in
  install | upgrade | uninstall) ;;
  *)
    echo "ERROR: unsupported action '$action'." >&2
    exit 64
    ;;
esac

case "$action" in
  install) action_label="Install" ;;
  upgrade) action_label="Upgrade" ;;
  uninstall) action_label="Uninstall" ;;
esac

usage() {
  cat <<EOF
Usage: ${action}.sh [options]

Interactively $action this repository's plugins in supported agent runtimes.
Plugin state is detected before any change.

Options:
  --runtime <name>  Limit $action to claude, codex, or copilot
  --plugin <name>   Limit $action to one marketplace plugin, or all
  --scope <scope>   Claude Code scope: user (default), project, or local
  --local           Register this checkout instead of akunzai/agent-skills
  --threshold <0-1> CodexBar quota threshold for install/upgrade (default: 0.9)
  --keep-state      Preserve CodexBar quota state during uninstall
  --interactive     Show selection prompts even when stdin is not a TTY
  --yes             Apply selected changes without confirmation
  -h, --help        Show this help
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"
marketplace_name="akunzai-agent-skills"
marketplace_source="akunzai/agent-skills"
runtime=""
plugin_filter=""
scope="user"
interactive=false
assume_yes=false
codexbar_threshold="0.9"
threshold_set=false
keep_state=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --runtime)
      runtime="${2:?--runtime requires claude, codex, or copilot}"
      shift 2
      ;;
    --runtime=*)
      runtime="${1#--runtime=}"
      shift
      ;;
    --plugin)
      plugin_filter="${2:?--plugin requires a plugin name or all}"
      shift 2
      ;;
    --plugin=*)
      plugin_filter="${1#--plugin=}"
      shift
      ;;
    --scope)
      scope="${2:?--scope requires user, project, or local}"
      shift 2
      ;;
    --scope=*)
      scope="${1#--scope=}"
      shift
      ;;
    --local)
      marketplace_source="$repo_root"
      shift
      ;;
    --threshold)
      codexbar_threshold="${2:?--threshold requires a value}"
      threshold_set=true
      shift 2
      ;;
    --threshold=*)
      codexbar_threshold="${1#--threshold=}"
      threshold_set=true
      shift
      ;;
    --keep-state)
      keep_state=true
      shift
      ;;
    --interactive)
      interactive=true
      shift
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required; install it before running ${action}.sh." >&2
  exit 69
fi
if [[ ! -f "$marketplace_json" ]]; then
  echo "ERROR: marketplace manifest not found: $marketplace_json" >&2
  exit 66
fi
if [[ -n "$runtime" && "$runtime" != "claude" && "$runtime" != "codex" && "$runtime" != "copilot" ]]; then
  echo "ERROR: unsupported runtime '$runtime' (expected claude, codex, or copilot)." >&2
  exit 64
fi
if [[ "$scope" != "user" && "$scope" != "project" && "$scope" != "local" ]]; then
  echo "ERROR: unsupported Claude Code scope '$scope'." >&2
  exit 64
fi
if [[ "$threshold_set" == true && "$action" == "uninstall" ]]; then
  echo "ERROR: --threshold is only valid for install and upgrade." >&2
  exit 64
fi
if [[ "$keep_state" == true && "$action" != "uninstall" ]]; then
  echo "ERROR: --keep-state is only valid for uninstall." >&2
  exit 64
fi
if ! [[ "$codexbar_threshold" =~ ^[0-9]*\.?[0-9]+$ ]] \
  || ! awk -v t="$codexbar_threshold" 'BEGIN { exit !(t > 0 && t <= 1) }'; then
  echo "ERROR: --threshold must be a number greater than 0 and at most 1, got: $codexbar_threshold" >&2
  exit 64
fi

runtime_label() {
  case "$1" in
    claude) echo "Claude Code" ;;
    codex) echo "Codex CLI" ;;
    copilot) echo "GitHub Copilot CLI" ;;
  esac
}

# Runtime command contracts are intentionally kept in these adapters. Current
# authoritative references:
# - Claude Code: https://code.claude.com/docs/en/plugin-marketplaces
# - Codex: https://developers.openai.com/codex/developer-commands?surface=cli#cli-codex-plugin-marketplace
# - Copilot CLI: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace
claude_list_plugins() { claude plugin list --json 2>/dev/null || echo '[]'; }
claude_list_marketplaces() { claude plugin marketplace list --json 2>/dev/null || echo '[]'; }
claude_is_installed() {
  jq -e --arg id "$1" --arg scope "$scope" \
    'any(.[]; .id == $id and .scope == $scope)' \
    <<<"$installed_output" >/dev/null 2>&1
}
claude_marketplace_registered() {
  jq -e --arg name "$marketplace_name" 'any(.[]; .name == $name)' \
    <<<"$marketplace_output" >/dev/null 2>&1
}
claude_add_marketplace() { claude plugin marketplace add "$marketplace_source"; }
claude_refresh_marketplace() { claude plugin marketplace update "$marketplace_name"; }
claude_install_plugin() { claude plugin install "$1" --scope "$scope" --yes; }
claude_upgrade_plugin() { claude plugin update "$1" --scope "$scope" --yes; }
claude_uninstall_plugin() { claude plugin uninstall "$1" --scope "$scope" --yes; }

codex_list_plugins() { codex plugin list --json 2>/dev/null || echo '{"installed":[]}'; }
codex_list_marketplaces() { codex plugin marketplace list --json 2>/dev/null || echo '{"marketplaces":[]}'; }
codex_is_installed() {
  jq -e --arg id "$1" \
    'any(.installed[]?; .pluginId == $id and .installed == true)' \
    <<<"$installed_output" >/dev/null 2>&1
}
codex_marketplace_registered() {
  jq -e --arg name "$marketplace_name" \
    'any(.marketplaces[]?; .name == $name)' \
    <<<"$marketplace_output" >/dev/null 2>&1
}
codex_add_marketplace() { codex plugin marketplace add "$marketplace_source"; }
codex_refresh_marketplace() { codex plugin marketplace upgrade "$marketplace_name"; }
codex_install_plugin() { codex plugin add "$1"; }
codex_upgrade_plugin() { :; }
codex_uninstall_plugin() { codex plugin remove "$1"; }

copilot_list_plugins() { copilot plugin list 2>/dev/null || true; }
copilot_list_marketplaces() { copilot plugin marketplace list 2>/dev/null || true; }
copilot_is_installed() { [[ "$installed_output" == *"$1"* ]]; }
copilot_marketplace_registered() { [[ "$marketplace_output" == *"$marketplace_name"* ]]; }
copilot_add_marketplace() { copilot plugin marketplace add "$marketplace_source"; }
copilot_refresh_marketplace() { copilot plugin marketplace update "$marketplace_name"; }
copilot_install_plugin() { copilot plugin install "$1"; }
copilot_upgrade_plugin() { copilot plugin update "$1"; }
copilot_uninstall_plugin() { copilot plugin uninstall "$1"; }

runtime_call() {
  local operation="$1"
  shift
  "${runtime}_${operation}" "$@"
}

plugins=()
while IFS= read -r name; do
  plugins+=("$name")
done < <(jq -r '.plugins[].name' "$marketplace_json")

if [[ ${#plugins[@]} -eq 0 ]]; then
  echo "ERROR: no plugins found in $marketplace_json" >&2
  exit 65
fi

if [[ -z "$runtime" ]]; then
  if [[ "$interactive" != true && ( ! -t 0 || ! -t 1 ) ]]; then
    echo "ERROR: choose a runtime with --runtime when ${action} is not interactive." >&2
    exit 64
  fi

  available_runtimes=()
  for candidate in claude codex copilot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      available_runtimes+=("$candidate")
    fi
  done
  if [[ ${#available_runtimes[@]} -eq 0 ]]; then
    echo "ERROR: none of claude, codex, or copilot were found on PATH." >&2
    exit 69
  fi

  echo ""
  echo "Detected agent runtimes:"
  index=1
  for candidate in "${available_runtimes[@]}"; do
    printf '  %s) %s\n' "$index" "$(runtime_label "$candidate")"
    index=$((index + 1))
  done
  printf 'Select a runtime to %s: ' "$action"
  read -r reply
  if ! [[ "$reply" =~ ^[0-9]+$ ]] \
    || (( reply < 1 || reply > ${#available_runtimes[@]} )); then
    echo "ERROR: invalid runtime selection '$reply'." >&2
    exit 64
  fi
  runtime="${available_runtimes[reply - 1]}"
fi

if ! command -v "$runtime" >/dev/null 2>&1; then
  echo "ERROR: $runtime CLI not found on PATH." >&2
  exit 69
fi

if [[ "$runtime" == "codex" ]]; then
  compatible_plugins=()
  for name in "${plugins[@]}"; do
    source_path="$(jq -r --arg name "$name" \
      '.plugins[] | select(.name == $name) | .source' "$marketplace_json")"
    source_path="${source_path#./}"
    if [[ -f "$repo_root/$source_path/.codex-plugin/plugin.json" ]]; then
      compatible_plugins+=("$name")
    fi
  done
  plugins=("${compatible_plugins[@]}")
fi

installed_output="$(runtime_call list_plugins)"
marketplace_output="$(runtime_call list_marketplaces)"

is_installed() {
  runtime_call is_installed "$1@$marketplace_name"
}

selected_plugins=()
if [[ -n "$plugin_filter" && "$plugin_filter" != "all" ]]; then
  found=false
  for name in "${plugins[@]}"; do
    if [[ "$name" == "$plugin_filter" ]]; then
      found=true
      selected_plugins+=("$name")
      break
    fi
  done
  if [[ "$found" == false ]]; then
    echo "ERROR: unknown or incompatible plugin '$plugin_filter' for $runtime." >&2
    exit 64
  fi
elif [[ "$interactive" == true || ( -t 0 && -t 1 ) ]]; then
  echo ""
  echo "Plugins available for $(runtime_label "$runtime"):"
  index=1
  for name in "${plugins[@]}"; do
    state="not installed"
    if is_installed "$name"; then
      state="installed"
    fi
    printf '  %s) %s [%s]\n' "$index" "$name" "$state"
    index=$((index + 1))
  done
  printf 'Select plugins (numbers separated by commas, or all): '
  read -r reply
  if [[ "$reply" == "all" || -z "$reply" ]]; then
    selected_plugins=("${plugins[@]}")
  else
    IFS=',' read -r -a selections <<<"$reply"
    for selection in "${selections[@]}"; do
      selection="${selection//[[:space:]]/}"
      if ! [[ "$selection" =~ ^[0-9]+$ ]] \
        || (( selection < 1 || selection > ${#plugins[@]} )); then
        echo "ERROR: invalid plugin selection '$selection'." >&2
        exit 64
      fi
      selected_plugins+=("${plugins[selection - 1]}")
    done
  fi
else
  selected_plugins=("${plugins[@]}")
fi

target_plugins=()
for name in "${selected_plugins[@]}"; do
  installed=false
  if is_installed "$name"; then
    installed=true
  fi
  case "$action" in
    install)
      if [[ "$installed" == true ]]; then
        echo "  already installed: $name@$marketplace_name"
      else
        target_plugins+=("$name")
      fi
      ;;
    upgrade | uninstall)
      if [[ "$installed" == true ]]; then
        target_plugins+=("$name")
      else
        echo "  not installed: $name@$marketplace_name"
      fi
      ;;
  esac
done

if [[ ${#target_plugins[@]} -eq 0 ]]; then
  echo "Nothing to $action for $runtime."
  exit 0
fi

if [[ "$action" == "upgrade" && "$runtime" == "codex" ]]; then
  echo "  Note: Codex upgrades the full $marketplace_name marketplace snapshot."
fi

if [[ "$assume_yes" == false ]]; then
  printf '%s %s plugin(s) for %s? [y/N] ' \
    "$action_label" "${#target_plugins[@]}" "$(runtime_label "$runtime")"
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "$action_label cancelled."
    exit 0
  fi
fi

case "$action" in
  install)
    if ! runtime_call marketplace_registered; then
      echo "  adding marketplace: $marketplace_source"
      runtime_call add_marketplace
    fi
    for name in "${target_plugins[@]}"; do
      echo "  installing $name@$marketplace_name"
      runtime_call install_plugin "$name@$marketplace_name"
    done
    ;;
  upgrade)
    if ! runtime_call marketplace_registered; then
      echo "  adding marketplace: $marketplace_source"
      runtime_call add_marketplace
    fi
    echo "  refreshing marketplace: $marketplace_name"
    runtime_call refresh_marketplace
    if [[ "$runtime" == "codex" ]]; then
      echo "  Codex refreshed the full marketplace snapshot."
    else
      for name in "${target_plugins[@]}"; do
        echo "  upgrading $name@$marketplace_name"
        runtime_call upgrade_plugin "$name@$marketplace_name"
      done
    fi
    ;;
  uninstall)
    for name in "${target_plugins[@]}"; do
      echo "  uninstalling $name@$marketplace_name"
      runtime_call uninstall_plugin "$name@$marketplace_name"
    done
    ;;
esac

if [[ "$runtime" == "codex" ]]; then
  for name in "${target_plugins[@]}"; do
    if [[ "$name" == "cheap-dev-workers" ]]; then
      case "$action" in
        install | upgrade)
          echo "  syncing cheap-dev-workers Codex personal agents..."
          bash "$repo_root/plugins/cheap-dev-workers/scripts/install-codex-agents.sh"
          ;;
        uninstall)
          echo "  removing cheap-dev-workers Codex personal agents..."
          bash "$repo_root/plugins/cheap-dev-workers/scripts/uninstall-codex-agents.sh"
          ;;
      esac
      break
    fi
  done
fi

for name in "${target_plugins[@]}"; do
  if [[ "$name" == "codexbar-quota-handoff" ]]; then
    case "$action" in
      install | upgrade)
        echo "  configuring codexbar-quota-handoff host integration..."
        bash "$repo_root/plugins/codexbar-quota-handoff/scripts/configure-host.sh" \
          --threshold "$codexbar_threshold"
        ;;
      uninstall)
        echo "  removing codexbar-quota-handoff host integration..."
        cleanup_args=()
        if [[ "$keep_state" == true ]]; then
          cleanup_args+=(--keep-state)
        fi
        bash "$repo_root/plugins/codexbar-quota-handoff/scripts/remove-host.sh" \
          "${cleanup_args[@]}"
        ;;
    esac
    break
  fi
done

echo "Done. Start a new $runtime session to pick up plugin changes."
