#!/bin/bash
# Unified Memory Autopilot - Cross-device Git Worktree Syncer
#
# This script synchronizes the local '.memories/' directory with a dedicated,
# isolated git branch ('project-memories') using git worktree.
# It ensures sync without switching your active development branch.

set -euo pipefail

BRANCH="project-memories"
MEMORY_PATH=".memories"

# Check if git repository exists
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Not a git repository."
  exit 1
fi

REPO_DIR="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git -C "$REPO_DIR" rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$REPO_DIR/$GIT_COMMON_DIR" ;;
esac

WORKTREE_DIR="$GIT_COMMON_DIR/memories-worktree"
LOCAL_DIR="$REPO_DIR/$MEMORY_PATH"

ensure_origin() {
  if ! git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
    echo "Error: remote 'origin' is required for memory sync."
    exit 1
  fi
}

create_memory_branch() {
  local init_worktree
  init_worktree="$(mktemp -d "$GIT_COMMON_DIR/memories-init.XXXXXX")"
  rmdir "$init_worktree"

  git -C "$REPO_DIR" worktree add --detach "$init_worktree" HEAD >/dev/null
  (
    cd "$init_worktree"
    git checkout --orphan "$BRANCH" >/dev/null
    git rm -rf . >/dev/null 2>&1 || true
    mkdir -p "$MEMORY_PATH"
    touch "$MEMORY_PATH/.gitkeep"
    git add "$MEMORY_PATH/.gitkeep"
    git commit -m "Initialize project-memories branch" >/dev/null
    git push origin "$BRANCH" >/dev/null
  )
  git -C "$REPO_DIR" worktree remove --force "$init_worktree" >/dev/null
}

setup_worktree() {
  ensure_origin
  if [ ! -d "$WORKTREE_DIR" ]; then
    echo "Initializing isolated memory worktree..."
    # Fetch the remote branch if it exists but is not present locally
    if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
      echo "Fetching remote branch '$BRANCH'..."
      git fetch origin "$BRANCH":"$BRANCH" || git fetch origin "$BRANCH"
    fi
    # Create orphan branch if it doesn't exist remotely or locally
    if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
      echo "Creating fresh orphan branch '$BRANCH'..."
      create_memory_branch
    fi
    # Add worktree linked to the isolated branch
    git worktree add -f "$WORKTREE_DIR" "$BRANCH"
  fi
}

ensure_clean_worktree() {
  local git_dir
  git_dir="$(git -C "$WORKTREE_DIR" rev-parse --git-dir)"
  case "$git_dir" in
    /*) ;;
    *) git_dir="$WORKTREE_DIR/$git_dir" ;;
  esac

  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ]; then
    echo "Error: Memory sync worktree has an unfinished merge or rebase at $WORKTREE_DIR." >&2
    echo "Resolve it there and continue, or run 'git -C \"$WORKTREE_DIR\" rebase --abort' before syncing again." >&2
    exit 1
  fi

  if [ -n "$(git -C "$WORKTREE_DIR" status --porcelain)" ]; then
    echo "Error: Memory sync worktree has uncommitted changes at $WORKTREE_DIR." >&2
    echo "Resolve or discard them before syncing again." >&2
    exit 1
  fi
}

commit_local_snapshot() {
  if [ ! -d "$LOCAL_DIR" ]; then
    echo "No local '$MEMORY_PATH' directory found. Only remote memories will be synced."
    return
  fi

  mkdir -p "$WORKTREE_DIR/$MEMORY_PATH"
  cp -R "$LOCAL_DIR/." "$WORKTREE_DIR/$MEMORY_PATH/"

  git -C "$WORKTREE_DIR" add "$MEMORY_PATH/"
  if git -C "$WORKTREE_DIR" diff --cached --quiet; then
    echo "No local daily log changes detected."
  else
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    git -C "$WORKTREE_DIR" commit -m "sync: local daily memories at $TIMESTAMP"
  fi
}

rebase_remote() {
  echo "Rebasing memory worktree with remote '$BRANCH'..."
  git -C "$WORKTREE_DIR" fetch origin "$BRANCH"
  if ! git -C "$WORKTREE_DIR" rebase "origin/$BRANCH"; then
    echo "Conflict detected in $WORKTREE_DIR." >&2
    echo "Resolve conflicts there, run 'git rebase --continue', then rerun this sync command." >&2
    echo "Local '$MEMORY_PATH' was not overwritten." >&2
    exit 1
  fi
}

sync_back_to_local() {
  if [ -d "$WORKTREE_DIR/$MEMORY_PATH" ]; then
    mkdir -p "$LOCAL_DIR"
    cp -R "$WORKTREE_DIR/$MEMORY_PATH/." "$LOCAL_DIR/"
  fi
}

sync_merge_remote() {
  setup_worktree
  ensure_clean_worktree
  commit_local_snapshot
  rebase_remote
}

sync_push() {
  echo "Syncing local memories -> remote '$BRANCH'..."
  sync_merge_remote
  git -C "$WORKTREE_DIR" push origin "$BRANCH"
  sync_back_to_local
  echo "Successfully pushed daily memories to remote."
}

sync_pull() {
  echo "Syncing remote '$BRANCH' -> local memories..."
  sync_merge_remote
  if [ -d "$WORKTREE_DIR/$MEMORY_PATH" ]; then
    sync_back_to_local
    echo "Successfully pulled and updated local daily memories."
  else
    echo "No remote daily memories found."
  fi
}

case "$1" in
  push)
    sync_push
    ;;
  pull)
    sync_pull
    ;;
  *)
    echo "Usage: $0 {push|pull}"
    exit 1
    ;;
esac
