#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: configure-host.sh [options]

Install the shared runtime helpers and configure CodexBar host integrations.

Options:
  --threshold <0-1>  Quota usage threshold (default: 0.9)
  -h, --help         Show this help
EOF
}

threshold="0.9"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --threshold)
      threshold="${2:?--threshold requires a value}"
      shift 2
      ;;
    --threshold=*)
      threshold="${1#--threshold=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if ! [[ "$threshold" =~ ^[0-9]*\.?[0-9]+$ ]] \
  || ! awk -v t="$threshold" 'BEGIN { exit !(t > 0 && t <= 1) }'; then
  echo "ERROR: --threshold must be a number greater than 0 and at most 1, got: $threshold" >&2
  exit 1
fi

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
  echo "ERROR: jq is required; install it before configuring the host integration." >&2
  exit 1
fi

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$data_home/codexbar-quota-handoff/scripts"
state_dir="$state_home/codexbar-quota-handoff"
codexbar_config="$HOME/.codexbar/config.json"
flag_writer="$runtime_dir/codexbar-quota-flag.sh"
providers=()
tmp_config=""
next_config=""

cleanup() {
  [[ -z "$tmp_config" ]] || rm -f "$tmp_config"
  [[ -z "$next_config" ]] || rm -f "$next_config"
}
trap cleanup EXIT

install_helpers() {
  local name="codexbar-quota-flag.sh"
  local source target temporary
  mkdir -p "$runtime_dir"
  source="$plugin_root/scripts/$name"
  target="$runtime_dir/$name"
  temporary="$(mktemp "$runtime_dir/.${name}.XXXXXX")"
  cp "$source" "$temporary"
  chmod 755 "$temporary"
  mv "$temporary" "$target"
  echo "  installed runtime helpers in $runtime_dir"
}

remove_leftover_grok_hooks() {
  # Older installs wrote a Stop-only global hook because Grok Build 1.0.x
  # never registered plugin marketplace hooks. Grok is not a supported
  # runtime; those files would make this reminder claim the Claude flag.
  local leftover
  for leftover in \
    "$HOME/.grok/hooks/codexbar-quota-handoff.json" \
    "$HOME/.grok/hooks/codexbar-quota-reminder.sh"; do
    if [[ -e "$leftover" ]]; then
      rm -f "$leftover"
      echo "  removed leftover $leftover"
    fi
  done
}

echo "== Shared runtime =="
install_helpers
remove_leftover_grok_hooks

echo "== Claude Code =="
if command -v claude >/dev/null 2>&1; then
  providers+=(claude)
else
  echo "  claude CLI not found on PATH; no CodexBar rule will be added."
fi

echo "== Codex CLI =="
if command -v codex >/dev/null 2>&1; then
  providers+=(codex)
else
  echo "  codex CLI not found on PATH; no CodexBar rule will be added."
fi

echo "== GitHub Copilot CLI =="
if command -v copilot >/dev/null 2>&1; then
  providers+=(copilot)
else
  echo "  copilot CLI not found on PATH; no CodexBar rule will be added."
fi

# Detect cursor-agent only — never a bare `agent` binary. Grok and Cursor
# both ship `agent`, so that name collides and cannot identify Cursor.
echo "== Cursor CLI =="
if command -v cursor-agent >/dev/null 2>&1; then
  providers+=(cursor)
else
  echo "  cursor-agent CLI not found on PATH; no CodexBar rule will be added."
fi

echo "== CodexBar =="
if [[ ${#providers[@]} -eq 0 ]]; then
  echo "  none of claude/codex/copilot/cursor-agent were found on PATH; nothing to configure."
  exit 0
fi
if ! command -v codexbar >/dev/null 2>&1; then
  echo "  codexbar CLI not found on PATH; skipping configuration."
  exit 0
fi
if [[ ! -f "$codexbar_config" ]]; then
  echo "  $codexbar_config not found; open CodexBar once, then re-run the repository setup."
  exit 0
fi
if [[ -L "$codexbar_config" ]]; then
  codexbar_config="$(realpath "$codexbar_config")"
fi

backup="${codexbar_config}.bak.$(date +%s)"
cp "$codexbar_config" "$backup"
echo "  backed up existing config to $backup"

tmp_config="$(mktemp "$(dirname "$codexbar_config")/.codexbar-quota-handoff.XXXXXX")"
cp "$codexbar_config" "$tmp_config"
chmod --reference="$codexbar_config" "$tmp_config" 2>/dev/null \
  || chmod "$(stat -f '%Lp' "$codexbar_config")" "$tmp_config"
for provider in "${providers[@]}"; do
  rule_id="agent-skills-codexbar-quota-handoff-${provider}"
  next_config="$(mktemp "$(dirname "$codexbar_config")/.codexbar-quota-handoff.XXXXXX")"
  jq \
    --arg id "$rule_id" \
    --arg provider "$provider" \
    --arg exe "$flag_writer" \
    --arg state_dir "$state_dir" \
    --argjson threshold "$threshold" \
    '
    .hooks.enabled = true
    | .hooks.events = ((.hooks.events // []) | map(
      select(.id != $id and .id != "agent-skills-codexbar-quota-handoff-grok")
    )) + [{
      id: $id,
      enabled: true,
      event: "quota_low",
      provider: $provider,
      threshold: $threshold,
      executable: $exe,
      arguments: [$provider, $state_dir],
      timeoutSeconds: 10
    }]
    ' "$tmp_config" >"$next_config"
  cat "$next_config" >"$tmp_config"
  rm "$next_config"
done
mv "$tmp_config" "$codexbar_config"
tmp_config=""
echo "  merged quota_low hook rules (threshold: $threshold) into $codexbar_config"

for provider in "${providers[@]}"; do
  guard_rc=0
  guard_output="$(codexbar guard --provider "$provider" --window weekly --json --timeout 10 --fail-open 2>/dev/null)" || guard_rc=$?
  if [[ $guard_rc -ne 0 ]] || ! printf '%s' "$guard_output" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "WARNING: CodexBar could not verify the $provider provider." >&2
  elif [[ -n "$(printf '%s' "$guard_output" | jq -r '.unavailableReason // empty')" ]]; then
    echo "WARNING: the $provider provider is not reachable in CodexBar." >&2
  fi
done

echo "Host integration configured. Start a new session or reload plugins."
