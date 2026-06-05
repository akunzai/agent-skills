#!/usr/bin/env bash
set -euo pipefail

# >>> posix-path-guard >>>
# On Windows (Git Bash / MSYS / Cygwin), make MSYS coreutils win over the
# native find.exe/tar.exe in C:\Windows\System32. Keep this block identical
# across scripts (verified by tests/windows-path-guard.sh).
case "${OSTYPE:-}" in
  msys*|cygwin*)
    if [ -x /usr/bin/sed ]; then
      PATH="/usr/bin:/bin:$PATH"
    elif command -v git >/dev/null 2>&1; then
      _git_root="$(dirname "$(dirname "$(command -v git)")")"
      [ -x "$_git_root/usr/bin/sed" ] && PATH="$_git_root/usr/bin:$_git_root/bin:$PATH"
      unset _git_root
    fi
    ;;
esac
# <<< posix-path-guard <<<

memory_file="${MEMORY_FILE:-$HOME/.agents/MEMORY.md}"

if [ -r "$memory_file" ] && [ -s "$memory_file" ]; then
  echo "# Long-term memory (~/.agents/MEMORY.md) — durable cross-project instructions; apply before responding."
  printf '%s\n' "$(<"$memory_file")"
fi

exit 0
