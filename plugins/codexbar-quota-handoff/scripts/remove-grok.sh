#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-grok.sh [options]

Remove leftover Grok Build files for this plugin without uninstalling it
from Claude Code, Codex, Copilot, or Cursor.

Removes the owned global hook files under ~/.grok/hooks/ and the CodexBar
grok rule. Prints the grok CLI command to drop this repository as a Grok
marketplace source; pass --yes to run that command when grok is on PATH.

Options:
  --yes          Run grok plugin marketplace remove when grok is on PATH
  -h, --help     Show this help
EOF
}

run_marketplace_remove=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) run_marketplace_remove=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required; install it before removing leftover Grok files." >&2
  exit 1
fi

codexbar_config="$HOME/.codexbar/config.json"
grok_hook="$HOME/.grok/hooks/codexbar-quota-handoff.json"
grok_script="$HOME/.grok/hooks/codexbar-quota-reminder.sh"
marketplace_cmd=(grok plugin marketplace remove akunzai-agent-skills)
temporary=""

cleanup() {
  [[ -z "$temporary" ]] || rm -f "$temporary"
}
trap cleanup EXIT

echo "== Grok hooks =="
removed_hooks=false
if [[ -e "$grok_hook" ]]; then
  rm -f "$grok_hook"
  echo "  removed $grok_hook"
  removed_hooks=true
fi
if [[ -e "$grok_script" ]]; then
  rm -f "$grok_script"
  echo "  removed $grok_script"
  removed_hooks=true
fi
if [[ "$removed_hooks" == false ]]; then
  echo "  no owned Grok global hook at $grok_hook"
fi

echo "== CodexBar =="
if [[ -f "$codexbar_config" ]]; then
  if [[ -L "$codexbar_config" ]]; then
    codexbar_config="$(realpath "$codexbar_config")"
  fi
  if jq -e '
    any((.hooks.events // [])[]; .id == "agent-skills-codexbar-quota-handoff-grok")
  ' "$codexbar_config" >/dev/null; then
    backup="${codexbar_config}.bak.$(date +%s)"
    cp "$codexbar_config" "$backup"
    echo "  backed up existing config to $backup"
    temporary="$(mktemp "$(dirname "$codexbar_config")/.codexbar-quota-handoff.XXXXXX")"
    chmod --reference="$codexbar_config" "$temporary" 2>/dev/null \
      || chmod "$(stat -f '%Lp' "$codexbar_config")" "$temporary"
    jq '
      .hooks.events = ((.hooks.events // []) | map(
        select(.id != "agent-skills-codexbar-quota-handoff-grok")
      ))
    ' "$codexbar_config" >"$temporary"
    mv "$temporary" "$codexbar_config"
    temporary=""
    echo "  removed the grok quota_low rule from $codexbar_config"
  else
    echo "  no grok quota_low rule in $codexbar_config"
  fi
else
  echo "  no CodexBar config at $codexbar_config"
fi

echo "== Grok marketplace =="
if command -v grok >/dev/null 2>&1; then
  if [[ "$run_marketplace_remove" == true ]]; then
    "${marketplace_cmd[@]}"
  else
    echo "  grok is on PATH. Drop this repository as a Grok marketplace source with:"
    echo "    ${marketplace_cmd[*]}"
    echo "  Re-run with --yes to run that command."
  fi
else
  echo "  grok CLI not found on PATH; skip marketplace removal."
  echo "  If Grok is installed later, run: ${marketplace_cmd[*]}"
fi

echo "Leftover Grok files removed. Reload Grok hooks or start a new session."
