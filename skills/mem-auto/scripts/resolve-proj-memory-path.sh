#!/usr/bin/env bash
set -euo pipefail

# resolve-proj-memory-path.sh
# Resolves global project short-term memory path (~/.agents/memories/projects/<proj-slug>/)
# Pure path resolution without side-effects (no directory creation, no legacy migration).

TARGET_DIR="${1:-$PWD}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory '$TARGET_DIR' does not exist." >&2
  exit 1
fi

# Resolve canonical absolute path of target dir
CANONICAL_TARGET="$(cd "$TARGET_DIR" && pwd -P)"

GIT_CMD="env -u GIT_DIR -u GIT_WORK_TREE -u GIT_PREFIX git -C $CANONICAL_TARGET"

# Resolve Git Main Repo Root (supports Git worktrees)
MAIN_REPO_ROOT=""
if $GIT_CMD rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMON_DIR="$($GIT_CMD rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$COMMON_DIR" ]; then
    # Make COMMON_DIR absolute if relative
    if [[ "$COMMON_DIR" != /* ]]; then
      COMMON_DIR="$CANONICAL_TARGET/$COMMON_DIR"
    fi
    ABS_COMMON_DIR="$(cd "$COMMON_DIR" 2>/dev/null && pwd -P || true)"
    if [ -n "$ABS_COMMON_DIR" ] && [ "$(basename "$ABS_COMMON_DIR")" = ".git" ]; then
      MAIN_REPO_ROOT="$(dirname "$ABS_COMMON_DIR")"
    fi
  fi

  if [ -z "$MAIN_REPO_ROOT" ]; then
    MAIN_REPO_ROOT="$($GIT_CMD rev-parse --show-toplevel 2>/dev/null || true)"
  fi
fi

if [ -z "$MAIN_REPO_ROOT" ]; then
  MAIN_REPO_ROOT="$CANONICAL_TARGET"
fi

# Compute deterministic <proj-slug>: <folder-basename>-<path-hash>
PROJ_NAME="$(basename "$MAIN_REPO_ROOT")"

HASH=""
if command -v md5sum >/dev/null 2>&1; then
  HASH="$(printf "%s" "$MAIN_REPO_ROOT" | md5sum | cut -c1-6)"
elif command -v md5 >/dev/null 2>&1; then
  HASH="$(printf "%s" "$MAIN_REPO_ROOT" | md5 | cut -c1-6)"
elif command -v shasum >/dev/null 2>&1; then
  HASH="$(printf "%s" "$MAIN_REPO_ROOT" | shasum -a 256 | cut -c1-6)"
else
  HASH="$(printf "%s" "$MAIN_REPO_ROOT" | cksum | cut -d' ' -f1 | cut -c1-6)"
fi

SLUG="${PROJ_NAME}-${HASH}"
GLOBAL_MEM_DIR="${HOME}/.agents/memories/projects/${SLUG}"

echo "$GLOBAL_MEM_DIR"
