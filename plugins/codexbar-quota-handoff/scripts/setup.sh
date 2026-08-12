#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup.sh [--threshold <0-1>]

Install the shared runtime helpers, write the Grok global Stop hook when
grok is on PATH, configure CodexBar host integrations, and print the Claude
Code and Codex marketplace commands.

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
  echo "ERROR: jq is required; install it before running setup.sh." >&2
  exit 1
fi

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$plugin_root/../.." && pwd)"
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
  local name source target temporary
  mkdir -p "$runtime_dir"
  for name in codexbar-quota-flag.sh quota-reminder.sh; do
    source="$plugin_root/scripts/$name"
    target="$runtime_dir/$name"
    temporary="$(mktemp "$runtime_dir/.${name}.XXXXXX")"
    cp "$source" "$temporary"
    chmod 755 "$temporary"
    mv "$temporary" "$target"
  done
  echo "  installed runtime helpers in $runtime_dir"
}

# Grok discovers plugin hooks but does not register them on the session
# dispatcher (observed on Grok Build 1.0.x). Install a Stop-only global hook
# that points at the shared runtime helper. PostToolUse is omitted on purpose:
# on Grok, exit 2 there is fail-open and would claim the flag before Stop can
# surface the reminder to the model.
install_grok_global_hook() {
  local hooks_dir="$HOME/.grok/hooks"
  local hook_path="$hooks_dir/codexbar-quota-handoff.json"
  local reminder="$runtime_dir/quota-reminder.sh"
  local temporary
  mkdir -p "$hooks_dir"
  temporary="$(mktemp "$hooks_dir/.codexbar-quota-handoff.XXXXXX")"
  jq -n --arg cmd "$reminder" '
    {
      hooks: {
        Stop: [
          {
            hooks: [
              { type: "command", command: $cmd }
            ]
          }
        ]
      }
    }
  ' >"$temporary"
  chmod 644 "$temporary"
  mv "$temporary" "$hook_path"
  echo "  installed Grok global Stop hook at $hook_path"
}

echo "== Shared runtime =="
install_helpers

echo "== Claude Code =="
if command -v claude >/dev/null 2>&1; then
  providers+=(claude)
else
  echo "  claude CLI not found on PATH; no CodexBar rule will be added."
fi

echo "== Grok Build =="
if command -v grok >/dev/null 2>&1; then
  providers+=(grok)
  install_grok_global_hook
else
  echo "  grok CLI not found on PATH; no CodexBar rule will be added."
fi

echo "== Codex CLI =="
if command -v codex >/dev/null 2>&1; then
  providers+=(codex)
else
  echo "  codex CLI not found on PATH; no CodexBar rule will be added."
fi

cat <<EOF

== Plugin marketplaces ==
Run these commands from this checkout when the corresponding CLI is installed.
Grok does not need a marketplace install; its reminder uses the global Stop
hook written above when grok is on PATH.

  claude plugin marketplace add "$repo_root"
  claude plugin install codexbar-quota-handoff@akunzai-agent-skills --scope user

  codex plugin marketplace add "$repo_root"
  codex plugin add codexbar-quota-handoff --marketplace akunzai-agent-skills
EOF

echo "== CodexBar =="
if [[ ${#providers[@]} -eq 0 ]]; then
  echo "  none of claude/grok/codex were found on PATH; nothing to configure."
  exit 0
fi
if ! command -v codexbar >/dev/null 2>&1; then
  echo "  codexbar CLI not found on PATH; skipping configuration."
  exit 0
fi
if [[ ! -f "$codexbar_config" ]]; then
  echo "  $codexbar_config not found; open CodexBar once, then re-run setup.sh."
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
    | .hooks.events = ((.hooks.events // []) | map(select(.id != $id))) + [{
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

echo "Done. Reload Claude/Codex plugins after the marketplace commands above;"
echo "for Grok, reload hooks (Hooks tab → r) or start a new session."
