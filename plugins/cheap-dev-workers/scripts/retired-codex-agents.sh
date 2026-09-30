#!/usr/bin/env bash
set -euo pipefail

# Run by install-codex-agents.sh and uninstall-codex-agents.sh. The optional
# argument is the Codex agents directory, default ~/.codex/agents/.
#
# Removes Codex personal agents this plugin shipped in earlier releases and no
# longer ships. Retired agents are removed only when their bytes match a
# released version; edited or unknown files are left in place.
# Exits 0 when it removed a file, 1 otherwise.

# SHA-256 of every released codex-agents/check-runner.toml.
retired_check_runner_sha256=(
  389bb2ec9140df2a8bb804be6c4fc90e28f73247b29805586bfa7e8abe5e56e0
  715a60db9d83b1db48117a1a20f29f5664062c33065ef8f5947d1dad8b87cbc0
  9fe88bb75c65535ae0ea085c745a0371f157aa99b125456e5b0072f65d6ca383
  dd168dc8e2655a1bdda5a2829a830c5a92a6a104deb27a12a3eb969c762aa0a7
)

# SHA-256 of every released codex-agents/commit-writer.toml.
retired_commit_writer_sha256=(
  7993e541df3dd8bcac36b39a6d1ad542ee524eb81be4c61816a20a2d78ab2fba
  dfb298674399b021c71be315d915570729740f168615167c108d3f4afa4863b1
  faa93800b151d556ccf3096452a8166e87724df45dc831c4920e98b7288e8404
)

dest="${1:-$HOME/.codex/agents}"
removed=1

for name in commit-writer check-runner; do
  target="$dest/$name.toml"
  [[ -f "$target" ]] || continue
  case "$name" in
    commit-writer) known_sha256=("${retired_commit_writer_sha256[@]}") ;;
    check-runner) known_sha256=("${retired_check_runner_sha256[@]}") ;;
  esac
  digest="$(shasum -a 256 "$target" | cut -d' ' -f1)"
  matched=false
  for known in "${known_sha256[@]}"; do
    if [[ "$digest" == "$known" ]]; then
      rm -f "$target"
      echo "  removed retired $target"
      removed=0
      matched=true
      break
    fi
  done
  if [[ "$matched" == false ]]; then
    echo "  kept $target: $name is retired, but this file differs from every released version; remove it yourself if it is not yours" >&2
  fi
done
exit "$removed"
