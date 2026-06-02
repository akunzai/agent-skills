#!/bin/bash
# Unified Memory Autopilot - Cross-device Git Worktree Syncer
#
# This script synchronizes the local '.memories/' directory with a dedicated,
# isolated git branch ('project-memories') using git worktree.
# It ensures sync without switching your active development branch.

set -e

WORKTREE_DIR=".git/memories-worktree"
BRANCH="project-memories"
LOCAL_DIR=".memories"

# Check if git repository exists
if [ ! -d ".git" ]; then
  echo "Error: Not a git repository."
  exit 1
fi

setup_worktree() {
  if [ ! -d "$WORKTREE_DIR" ]; then
    echo "Initializing isolated memory worktree..."
    # Fetch the remote branch if it exists but is not present locally
    if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
      echo "Fetching remote branch '$BRANCH'..."
      git fetch origin "$BRANCH":"$BRANCH" || true
    fi
    # Create orphan branch if it doesn't exist remotely or locally
    if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
      echo "Creating fresh orphan branch '$BRANCH'..."
      # Create an empty branch with no parent history
      git checkout --orphan "$BRANCH"
      git rm -rf . >/dev/null 2>&1 || true
      # Create placeholder
      mkdir -p "$LOCAL_DIR"
      touch "$LOCAL_DIR/.gitkeep"
      git add "$LOCAL_DIR/.gitkeep"
      git commit -m "Initialize project-memories branch"
      git push origin "$BRANCH"
      # Switch back to previous active branch
      git checkout -
    fi
    # Add worktree linked to the isolated branch
    git worktree add -f "$WORKTREE_DIR" "$BRANCH"
  fi
}

sync_push() {
  setup_worktree
  if [ ! -d "$LOCAL_DIR" ]; then
    echo "Warning: Local '$LOCAL_DIR' directory does not exist. Nothing to push."
    return
  fi
  
  # Ensure the worktree is completely up-to-date with remote first
  echo "Pulling remote changes to prevent overwriting..."
  cd "$WORKTREE_DIR"
  git pull origin "$BRANCH" || echo "Warning: git pull had conflicts, proceeding..."
  cd - >/dev/null

  echo "Syncing local memories -> remote '$BRANCH'..."
  # Incremental copy: copy local memories but DO NOT delete existing files in worktree
  mkdir -p "$WORKTREE_DIR/.memories"
  cp -R "$LOCAL_DIR/." "$WORKTREE_DIR/.memories/"
  
  # Commit and push in the worktree directory
  cd "$WORKTREE_DIR"
  git add .memories/
  if git diff-index --quiet HEAD --; then
    echo "No daily log changes detected. Skip push."
  else
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    git commit -m "sync: daily memories at $TIMESTAMP"
    git push origin "$BRANCH"
    echo "Successfully pushed daily memories to remote."
  fi
  cd - >/dev/null
}

sync_pull() {
  setup_worktree
  echo "Syncing remote '$BRANCH' -> local memories..."
  
  # Pull updates in the worktree directory
  cd "$WORKTREE_DIR"
  git pull origin "$BRANCH"
  cd - >/dev/null

  # Copy back to main directory if memories exist in worktree
  if [ -d "$WORKTREE_DIR/.memories" ]; then
    mkdir -p "$LOCAL_DIR"
    cp -R "$WORKTREE_DIR/.memories/." "$LOCAL_DIR/"
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
