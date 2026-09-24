#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/agents-memory/scripts/proj-memory-path.sh"

fail() {
  echo "agents-memory-storage test failed: $*" >&2
  exit 1
}

if [ ! -x "$SCRIPT" ]; then
  fail "Script $SCRIPT is missing or not executable"
fi

# Isolated temporary HOME directory to avoid touching user's real ~/.agents/
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/mock_home"
mkdir -p "$HOME"

# Test 1: Pure Resolution (Non-Git Standalone Directory)
NON_GIT_DIR="$TMP_DIR/standalone_proj"
mkdir -p "$NON_GIT_DIR"

RES_NON_GIT="$("$SCRIPT" "$NON_GIT_DIR")"
echo "$RES_NON_GIT" | grep -q "$HOME/.agents/memories/projects/standalone_proj-" \
  || fail "Non-git directory resolution path failed: $RES_NON_GIT"

[ ! -d "$RES_NON_GIT" ] || fail "Pure resolver should not create global memory directory automatically"

# --ensure creates directory
ENS_NON_GIT="$("$SCRIPT" --ensure "$NON_GIT_DIR")"
[ "$RES_NON_GIT" = "$ENS_NON_GIT" ] || fail "Ensure path ($ENS_NON_GIT) does not match resolve path ($RES_NON_GIT)"
[ -d "$ENS_NON_GIT" ] || fail "Ensure failed to create global memory directory"

# Test 2 & 3: Git Repo and Git Worktree Resolution
GIT_REPO_DIR="$TMP_DIR/main_repo"
mkdir -p "$GIT_REPO_DIR"
git -C "$GIT_REPO_DIR" init -b main >/dev/null
git -C "$GIT_REPO_DIR" config user.email "test@example.com"
git -C "$GIT_REPO_DIR" config user.name "Test User"
touch "$GIT_REPO_DIR/README.md"
git -C "$GIT_REPO_DIR" add README.md
git -C "$GIT_REPO_DIR" commit -m "initial commit" >/dev/null

MAIN_MEM_PATH="$("$SCRIPT" "$GIT_REPO_DIR")"

WORKTREE_DIR="$TMP_DIR/worktree_repo"
git -C "$GIT_REPO_DIR" worktree add -b feat-test "$WORKTREE_DIR" >/dev/null 2>&1

WORKTREE_MEM_PATH="$("$SCRIPT" "$WORKTREE_DIR")"

if [ "$MAIN_MEM_PATH" != "$WORKTREE_MEM_PATH" ]; then
  fail "Git worktree memory path ($WORKTREE_MEM_PATH) does not match main repo memory path ($MAIN_MEM_PATH)"
fi

# Test 4: --ensure idempotency (re-running returns the same path, makes no changes)
IDEMPOTENT_PATH="$("$SCRIPT" --ensure "$GIT_REPO_DIR")"
if [ "$IDEMPOTENT_PATH" != "$MAIN_MEM_PATH" ]; then
  fail "Idempotent run returned different path: $IDEMPOTENT_PATH vs $MAIN_MEM_PATH"
fi
[ -d "$IDEMPOTENT_PATH" ] || fail "Ensure did not create the directory on the git-repo path"

# Test 5: flag may appear after DIR
FLAG_AFTER_DIR="$("$SCRIPT" "$NON_GIT_DIR" --ensure)"
[ "$FLAG_AFTER_DIR" = "$RES_NON_GIT" ] || fail "Flag-after-DIR path mismatch: $FLAG_AFTER_DIR"

# Test 6: unknown option fails
if "$SCRIPT" --bogus "$NON_GIT_DIR" >/dev/null 2>&1; then
  fail "Unknown option should fail"
fi

# Test 7: repo path containing a space, resolved both from the repo root and
# from a subdirectory and a linked worktree beneath it. The unquoted
# `$GIT_CMD rev-parse ...` word-splits a space in the path, so git silently
# fails (2>/dev/null || true) and MAIN_REPO_ROOT falls back to the target
# directory itself instead of the real repo root -- giving the subdirectory
# and the worktree a different slug than the main repo root.
SPACE_REPO_DIR="$TMP_DIR/repo with space"
mkdir -p "$SPACE_REPO_DIR/sub dir"
git -C "$SPACE_REPO_DIR" init -b main >/dev/null
git -C "$SPACE_REPO_DIR" config user.email "test@example.com"
git -C "$SPACE_REPO_DIR" config user.name "Test User"
touch "$SPACE_REPO_DIR/README.md"
git -C "$SPACE_REPO_DIR" add README.md
git -C "$SPACE_REPO_DIR" commit -m "initial commit" >/dev/null

SPACE_MAIN_MEM_PATH="$("$SCRIPT" "$SPACE_REPO_DIR")"
SPACE_SUBDIR_MEM_PATH="$("$SCRIPT" "$SPACE_REPO_DIR/sub dir")"
if [ "$SPACE_MAIN_MEM_PATH" != "$SPACE_SUBDIR_MEM_PATH" ]; then
  fail "Space-in-path subdirectory memory path ($SPACE_SUBDIR_MEM_PATH) does not match main repo memory path ($SPACE_MAIN_MEM_PATH)"
fi

SPACE_WORKTREE_DIR="$TMP_DIR/work tree with space"
git -C "$SPACE_REPO_DIR" worktree add -b feat-space-test "$SPACE_WORKTREE_DIR" >/dev/null 2>&1

SPACE_WORKTREE_MEM_PATH="$("$SCRIPT" "$SPACE_WORKTREE_DIR")"
if [ "$SPACE_MAIN_MEM_PATH" != "$SPACE_WORKTREE_MEM_PATH" ]; then
  fail "Space-in-path worktree memory path ($SPACE_WORKTREE_MEM_PATH) does not match main repo memory path ($SPACE_MAIN_MEM_PATH)"
fi

echo "agents-memory-storage tests passed"
