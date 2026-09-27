#!/usr/bin/env bash
set -euo pipefail

# Run by install-codex-agents.sh and uninstall-codex-agents.sh. The optional
# argument is the Codex agents directory, default ~/.codex/agents/.
#
# Removes Codex personal agents this plugin shipped in earlier releases and no
# longer ships. commit-writer.toml is removed unconditionally, as before.
# check-runner.toml is removed only when its bytes match a released version;
# anything else was edited or installed by the user and is left in place.
# Exits 0 when it removed a file, 1 otherwise.

# SHA-256 of every released codex-agents/check-runner.toml.
retired_check_runner_sha256=(
  389bb2ec9140df2a8bb804be6c4fc90e28f73247b29805586bfa7e8abe5e56e0
  715a60db9d83b1db48117a1a20f29f5664062c33065ef8f5947d1dad8b87cbc0
  9fe88bb75c65535ae0ea085c745a0371f157aa99b125456e5b0072f65d6ca383
  dd168dc8e2655a1bdda5a2829a830c5a92a6a104deb27a12a3eb969c762aa0a7
)

dest="${1:-$HOME/.codex/agents}"
removed=1

target="$dest/commit-writer.toml"
if [[ -e "$target" ]]; then
  rm -f "$target"
  echo "  removed leftover $target"
  removed=0
fi

target="$dest/check-runner.toml"
if [[ -f "$target" ]]; then
  digest="$(shasum -a 256 "$target" | cut -d' ' -f1)"
  for known in "${retired_check_runner_sha256[@]}"; do
    if [[ "$digest" == "$known" ]]; then
      rm -f "$target"
      echo "  removed retired $target"
      exit 0
    fi
  done
  echo "  kept $target: check-runner is retired, but this file differs from every released version; remove it yourself if it is not yours" >&2
fi
exit "$removed"
