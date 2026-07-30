#!/usr/bin/env bash
set -euo pipefail

# migrate-legacy-proj-memory.sh
# Performs legacy migration and cleanup for project short-term memory.
# Migrates legacy <repo>/.memories/ to global location and cleans up old worktrees/branches.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$PWD}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory '$TARGET_DIR' does not exist." >&2
  exit 1
fi

GLOBAL_MEM_DIR="$("$SCRIPT_DIR/resolve-proj-memory-path.sh" "$TARGET_DIR")"

# Canonical target and Git resolution for repo root
CANONICAL_TARGET="$(cd "$TARGET_DIR" && pwd -P)"
GIT_CMD="env -u GIT_DIR -u GIT_WORK_TREE -u GIT_PREFIX git -C $CANONICAL_TARGET"

MAIN_REPO_ROOT=""
if $GIT_CMD rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMON_DIR="$($GIT_CMD rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$COMMON_DIR" ]; then
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

# One-time legacy migration & cleanup if <repo>/.memories/ exists
LEGACY_DIR="${MAIN_REPO_ROOT}/.memories"
if [ -d "$LEGACY_DIR" ]; then
  mkdir -p "$GLOBAL_MEM_DIR"
  find "$LEGACY_DIR" -mindepth 1 -maxdepth 1 ! -name ".memories" | while read -r item; do
    if [ -n "$item" ]; then
      cp -rn "$item" "$GLOBAL_MEM_DIR/" 2>/dev/null || true
    fi
  done
  rm -rf "$LEGACY_DIR"
fi

# Remove leftover mem-sync worktree if present
if $GIT_CMD rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -d "${MAIN_REPO_ROOT}/.git/memories-worktree" ]; then
    $GIT_CMD worktree remove --force "${MAIN_REPO_ROOT}/.git/memories-worktree" 2>/dev/null || rm -rf "${MAIN_REPO_ROOT}/.git/memories-worktree"
    $GIT_CMD worktree prune 2>/dev/null || true
  fi
fi

# Check for leftover memories/* branches in git repo
if $GIT_CMD rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  LEGACY_BRANCHES="$($GIT_CMD branch --list "memories/*" 2>/dev/null | tr -d ' *' || true)"
  if [ -n "$LEGACY_BRANCHES" ]; then
    echo "[Notice] Legacy memory sync branch(es) found: ${LEGACY_BRANCHES}. You can clean up local/remote memories branches if no longer needed." >&2
  fi
fi
