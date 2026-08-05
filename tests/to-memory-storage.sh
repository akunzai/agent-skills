#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT_DIR/skills/to-memory/scripts/resolve-proj-memory-path.sh"
ENSURER="$ROOT_DIR/skills/to-memory/scripts/ensure-proj-memory-path.sh"

fail() {
  echo "to-memory-storage test failed: $*" >&2
  exit 1
}

if [ ! -x "$RESOLVER" ]; then
  fail "Resolver script $RESOLVER is missing or not executable"
fi

if [ ! -x "$ENSURER" ]; then
  fail "Ensurer script $ENSURER is missing or not executable"
fi

# Isolated temporary HOME directory to avoid touching user's real ~/.agents/
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/mock_home"
mkdir -p "$HOME"

# Test 1: Pure Resolution (Non-Git Standalone Directory)
NON_GIT_DIR="$TMP_DIR/standalone_proj"
mkdir -p "$NON_GIT_DIR"

RES_NON_GIT="$("$RESOLVER" "$NON_GIT_DIR")"
echo "$RES_NON_GIT" | grep -q "$HOME/.agents/memories/projects/standalone_proj-" \
  || fail "Non-git directory resolution path failed: $RES_NON_GIT"

[ ! -d "$RES_NON_GIT" ] || fail "Pure resolver should not create global memory directory automatically"

# Ensurer creates directory
ENS_NON_GIT="$("$ENSURER" "$NON_GIT_DIR")"
[ "$RES_NON_GIT" = "$ENS_NON_GIT" ] || fail "Ensurer path ($ENS_NON_GIT) does not match resolver path ($RES_NON_GIT)"
[ -d "$ENS_NON_GIT" ] || fail "Ensurer failed to create global memory directory"

# Test 2 & 3: Git Repo and Git Worktree Resolution
GIT_REPO_DIR="$TMP_DIR/main_repo"
mkdir -p "$GIT_REPO_DIR"
git -C "$GIT_REPO_DIR" init -b main >/dev/null
git -C "$GIT_REPO_DIR" config user.email "test@example.com"
git -C "$GIT_REPO_DIR" config user.name "Test User"
touch "$GIT_REPO_DIR/README.md"
git -C "$GIT_REPO_DIR" add README.md
git -C "$GIT_REPO_DIR" commit -m "initial commit" >/dev/null

MAIN_MEM_PATH="$("$RESOLVER" "$GIT_REPO_DIR")"

WORKTREE_DIR="$TMP_DIR/worktree_repo"
git -C "$GIT_REPO_DIR" worktree add -b feat-test "$WORKTREE_DIR" >/dev/null 2>&1

WORKTREE_MEM_PATH="$("$RESOLVER" "$WORKTREE_DIR")"

if [ "$MAIN_MEM_PATH" != "$WORKTREE_MEM_PATH" ]; then
  fail "Git worktree memory path ($WORKTREE_MEM_PATH) does not match main repo memory path ($MAIN_MEM_PATH)"
fi

# Test 4: Ensurer idempotency (re-running returns the same path, makes no changes)
IDEMPOTENT_PATH="$("$ENSURER" "$GIT_REPO_DIR")"
if [ "$IDEMPOTENT_PATH" != "$MAIN_MEM_PATH" ]; then
  fail "Idempotent run returned different path: $IDEMPOTENT_PATH vs $MAIN_MEM_PATH"
fi
[ -d "$IDEMPOTENT_PATH" ] || fail "Ensurer did not create the directory on the git-repo path"

echo "to-memory-storage tests passed"
