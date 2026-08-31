#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-host.sh [options]

Remove the shared runtime helpers, Grok global hook, and CodexBar rules.

Options:
  --keep-state       Preserve quota flag files
  -h, --help         Show this help
EOF
}

keep_state=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-state) keep_state=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
if [[ "$data_home" != /* ]]; then
  echo "ERROR: XDG_DATA_HOME must be an absolute path: $data_home" >&2
  exit 1
fi
if [[ "$state_home" != /* ]]; then
  echo "ERROR: XDG_STATE_HOME must be an absolute path: $state_home" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required; install it before removing the host integration." >&2
  exit 1
fi

runtime_root="$data_home/codexbar-quota-handoff"
state_dir="$state_home/codexbar-quota-handoff"
codexbar_config="$HOME/.codexbar/config.json"
grok_hook="$HOME/.grok/hooks/codexbar-quota-handoff.json"
grok_script="$HOME/.grok/hooks/codexbar-quota-reminder.sh"
temporary=""

cleanup() {
  [[ -z "$temporary" ]] || rm -f "$temporary"
}
trap cleanup EXIT

echo "== CodexBar =="
if [[ -f "$codexbar_config" ]]; then
  if [[ -L "$codexbar_config" ]]; then
    codexbar_config="$(realpath "$codexbar_config")"
  fi
  backup="${codexbar_config}.bak.$(date +%s)"
  cp "$codexbar_config" "$backup"
  temporary="$(mktemp "$(dirname "$codexbar_config")/.codexbar-quota-handoff.XXXXXX")"
  chmod --reference="$codexbar_config" "$temporary" 2>/dev/null \
    || chmod "$(stat -f '%Lp' "$codexbar_config")" "$temporary"
  jq '
    .hooks.events = ((.hooks.events // []) | map(
      select(.id != "agent-skills-codexbar-quota-handoff-claude"
      and .id != "agent-skills-codexbar-quota-handoff-grok"
      and .id != "agent-skills-codexbar-quota-handoff-codex"
      and .id != "agent-skills-codexbar-quota-handoff-copilot")
    ))
  ' "$codexbar_config" >"$temporary"
  mv "$temporary" "$codexbar_config"
  temporary=""
  echo "  removed this plugin's quota_low rules from $codexbar_config"
fi

echo "== Grok Build =="
removed_grok=false
if [[ -e "$grok_hook" ]]; then
  rm -f "$grok_hook"
  echo "  removed $grok_hook"
  removed_grok=true
fi
if [[ -e "$grok_script" ]]; then
  rm -f "$grok_script"
  echo "  removed $grok_script"
  removed_grok=true
fi
if [[ "$removed_grok" == false ]]; then
  echo "  no owned Grok global hook at $grok_hook"
fi

echo "== Shared runtime =="
if [[ -d "$runtime_root" && ! -L "$runtime_root" ]]; then
  rm -r "$runtime_root"
  echo "  removed $runtime_root"
fi
if [[ "$keep_state" == false && -d "$state_dir" && ! -L "$state_dir" ]]; then
  rm -r "$state_dir"
  echo "  removed $state_dir"
elif [[ "$keep_state" == true ]]; then
  echo "  preserving $state_dir"
fi

echo "Host integration removed."
