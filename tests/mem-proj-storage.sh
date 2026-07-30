#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT_DIR/skills/mem-auto/scripts/resolve-proj-memory-path.sh"

fail() {
  echo "mem-proj-storage test failed: $*" >&2
  exit 1
}

if [ ! -x "$RESOLVER" ]; then
  fail "Resolver script $RESOLVER is missing or not executable"
fi

# Isolated temporary HOME directory to avoid touching user's real ~/.agents/
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/mock_home"
mkdir -p "$HOME"

# Test 1: Non-Git Standalone Directory
NON_GIT_DIR="$TMP_DIR/standalone_proj"
mkdir -p "$NON_GIT_DIR"

RES_NON_GIT="$("$RESOLVER" "$NON_GIT_DIR")"
echo "$RES_NON_GIT" | grep -q "$HOME/.agents/memories/projects/standalone_proj-" \
  || fail "Non-git directory resolution path failed: $RES_NON_GIT"

[ -d "$RES_NON_GIT" ] || fail "Resolved global memory directory was not created"

# Test 2 & 3: Git Repo and Git Worktree
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

# Test 4: Legacy Migration & Cleanup
LEGACY_REPO="$TMP_DIR/legacy_repo"
mkdir -p "$LEGACY_REPO/.memories/handoffs"
git -C "$LEGACY_REPO" init -b main >/dev/null
git -C "$LEGACY_REPO" config user.email "test@example.com"
git -C "$LEGACY_REPO" config user.name "Test User"

echo "Candidate note 1" > "$LEGACY_REPO/.memories/2026-07-30.md"
echo "Handoff note 1" > "$LEGACY_REPO/.memories/handoffs/2026-07-30__task.md"

LEGACY_MEM_PATH="$("$RESOLVER" "$LEGACY_REPO")"

[ ! -d "$LEGACY_REPO/.memories" ] || fail "Legacy .memories directory was not removed from repository"
[ -f "$LEGACY_MEM_PATH/2026-07-30.md" ] || fail "Legacy 2026-07-30.md log was not migrated to $LEGACY_MEM_PATH"
[ -f "$LEGACY_MEM_PATH/handoffs/2026-07-30__task.md" ] || fail "Legacy handoff file was not migrated to $LEGACY_MEM_PATH/handoffs/"

# Test 5: Idempotency
IDEMPOTENT_PATH="$("$RESOLVER" "$LEGACY_REPO")"
if [ "$IDEMPOTENT_PATH" != "$LEGACY_MEM_PATH" ]; then
  fail "Idempotent run returned different path: $IDEMPOTENT_PATH vs $LEGACY_MEM_PATH"
fi

echo "mem-proj-storage tests passed"
