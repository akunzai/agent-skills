#!/usr/bin/env bash
# Unified Memory Autopilot - Cross-device Git Worktree Syncer
#
# This script synchronizes the local '.memories/' directory with a dedicated,
# isolated per-user git branch ('memories/<email-localpart>') using git worktree.
# It ensures sync without switching your active development branch.

set -euo pipefail

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

derive_branch() {
  local email slug
  email="$(git -C "$REPO_DIR" config user.email 2>/dev/null || true)"
  slug="$(printf '%s' "${email%%@*}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [ -z "$slug" ]; then
    echo "Error: git config user.email is required to derive the per-user memory branch." >&2
    exit 1
  fi
  printf 'memories/%s' "$slug"
}

BRANCH="$(derive_branch)"
REMOTE="${MEM_SYNC_REMOTE:-origin}"

WORKTREE_DIR="$GIT_COMMON_DIR/memories-worktree"
LOCAL_DIR="$REPO_DIR/$MEMORY_PATH"

ensure_remote() {
  if ! git -C "$REPO_DIR" remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "Error: remote '$REMOTE' is required for memory sync."
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
    git add -f "$MEMORY_PATH/.gitkeep"
    git commit -m "Initialize memory sync branch" >/dev/null
    git push "$REMOTE" "$BRANCH" >/dev/null
  )
  git -C "$REPO_DIR" worktree remove --force "$init_worktree" >/dev/null
}

setup_worktree() {
  ensure_remote
  if [ ! -d "$WORKTREE_DIR" ]; then
    echo "Initializing isolated memory worktree..."
    # Fetch the remote branch if it exists but is not present locally
    if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
      echo "Fetching remote branch '$BRANCH'..."
      git fetch "$REMOTE" "$BRANCH":"$BRANCH" || git fetch "$REMOTE" "$BRANCH"
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

  git -C "$WORKTREE_DIR" add -f "$MEMORY_PATH/"
  if git -C "$WORKTREE_DIR" diff --cached --quiet; then
    echo "No local daily log changes detected."
  else
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    git -C "$WORKTREE_DIR" commit -m "sync: local daily memories at $TIMESTAMP"
  fi
}

rebase_remote() {
  echo "Rebasing memory worktree with remote '$BRANCH'..."
  git -C "$WORKTREE_DIR" fetch "$REMOTE" "$BRANCH"
  if ! git -C "$WORKTREE_DIR" merge-base HEAD "$REMOTE/$BRANCH" >/dev/null 2>&1; then
    echo "Remote '$BRANCH' was rewritten (no common ancestor); adopting it authoritatively."
    git -C "$WORKTREE_DIR" reset --hard "$REMOTE/$BRANCH"
    return
  fi
  if ! git -C "$WORKTREE_DIR" rebase "$REMOTE/$BRANCH"; then
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
  git -C "$WORKTREE_DIR" push "$REMOTE" "$BRANCH"
  sync_back_to_local
  echo "Successfully pushed daily memories to remote."
}

sync_pull() {
  echo "Syncing remote '$BRANCH' -> local memories..."
  sync_merge_remote
  if [ -d "$WORKTREE_DIR/$MEMORY_PATH" ]; then
    rm -rf "${LOCAL_DIR:?}"
    mkdir -p "$LOCAL_DIR"
    cp -R "$WORKTREE_DIR/$MEMORY_PATH/." "$LOCAL_DIR/"
    find "$LOCAL_DIR" -name '.gitkeep' -delete 2>/dev/null || true
    echo "Successfully pulled and updated local daily memories."
  else
    echo "No remote daily memories found."
  fi
}

sync_compact() {
  echo "Compacting '$BRANCH' to a single authoritative commit..."
  setup_worktree
  ensure_clean_worktree
  # Replace worktree contents with the current local snapshot.
  rm -rf "${WORKTREE_DIR:?}/$MEMORY_PATH"
  mkdir -p "$WORKTREE_DIR/$MEMORY_PATH"
  if [ -d "$LOCAL_DIR" ]; then
    cp -R "$LOCAL_DIR/." "$WORKTREE_DIR/$MEMORY_PATH/"
  fi
  touch "$WORKTREE_DIR/$MEMORY_PATH/.gitkeep"
  # Rebuild history as a single orphan commit.
  # Clean up any stale compact-tmp branch left by a prior interrupted run.
  git -C "$WORKTREE_DIR" checkout "$BRANCH" >/dev/null 2>&1 || true
  git -C "$WORKTREE_DIR" branch -D "compact-tmp" >/dev/null 2>&1 || true
  git -C "$WORKTREE_DIR" checkout --orphan "compact-tmp" >/dev/null
  git -C "$WORKTREE_DIR" add -Af
  git -C "$WORKTREE_DIR" commit -m "compact: authoritative memory snapshot $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null
  git -C "$WORKTREE_DIR" branch -M "$BRANCH"
  git -C "$WORKTREE_DIR" push --force "$REMOTE" "$BRANCH"
  echo "Force-pushed compacted '$BRANCH'. Other devices will adopt it on next sync."
}

sync_status() {
  # Read-only: compares local .memories/ against the remote per-user branch.
  # mode "summary" prints a per-file overview; mode "diff" prints the full unified diff.
  local mode="${1:-summary}"
  ensure_remote

  if ! git -C "$REPO_DIR" ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
    echo "Remote branch '$BRANCH' does not exist on '$REMOTE' yet."
    if [ -d "$LOCAL_DIR" ]; then
      local n
      n="$(find "$LOCAL_DIR" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')"
      echo "Local has $n daily log file(s) not yet pushed."
    fi
    return 0
  fi

  git -C "$REPO_DIR" fetch -q "$REMOTE" "$BRANCH"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN
  mkdir -p "$tmp/$MEMORY_PATH" "$LOCAL_DIR"
  git -C "$REPO_DIR" archive "$REMOTE/$BRANCH" -- "$MEMORY_PATH" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null || true

  if [ "$mode" = "diff" ]; then
    diff -ru "$tmp/$MEMORY_PATH" "$LOCAL_DIR" || true
    return 0
  fi

  local out
  out="$(diff -rq "$tmp/$MEMORY_PATH" "$LOCAL_DIR" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    echo "In sync with '$REMOTE/$BRANCH'."
  else
    echo "Differences vs '$REMOTE/$BRANCH' (run 'diff' for full content):"
    printf '%s\n' "$out" \
      | sed -e "s#Only in $tmp/$MEMORY_PATH:#  remote-only:#" \
            -e "s#Only in $LOCAL_DIR:#  local-only :#" \
            -e "s#^Files .*/\(.*\) and .* differ#  modified   : \1#"
  fi
}

case "${1:-status}" in
  push)
    sync_push
    ;;
  pull)
    sync_pull
    ;;
  compact)
    sync_compact
    ;;
  status)
    sync_status summary
    ;;
  diff)
    sync_status diff
    ;;
  print-branch)
    printf '%s\n' "$BRANCH"
    ;;
  *)
    echo "Usage: $0 {push|pull|compact|status|diff|print-branch}"
    exit 1
    ;;
esac
