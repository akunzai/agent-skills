#!/usr/bin/env bash
# Invoked directly by CodexBar's own hooks system (not by any consuming tool)
# when its quota_low event fires for one of the monitored providers. CodexBar
# execs this file without a shell and with a minimal, GUI-app PATH, so this
# stays dependency-free: it just persists CodexBar's HookEvent JSON payload
# (stdin) verbatim, to a path keyed by the provider argument each CodexBar
# hook rule passes.
set -euo pipefail

provider="${1:?Usage: codexbar-quota-flag.sh <provider> [state-dir]}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
[[ "$state_home" == /* ]] || state_home="$HOME/.local/state"
state_dir="${2:-$state_home/codexbar-quota-handoff}"
flag_path="${CODEXBAR_QUOTA_FLAG_PATH:-$state_dir/quota-low-${provider}.json}"

mkdir -p "$(dirname "$flag_path")"
cat >"$flag_path"
