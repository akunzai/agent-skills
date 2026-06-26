#!/usr/bin/env bash
# Unified Memory Autopilot - Cross-device Git Worktree Syncer
#
# This script synchronizes the local '.memories/' directory with a dedicated,
# isolated per-user git branch ('memories/<email-localpart>') using git worktree.
# It ensures sync without switching your active development branch.

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

_msg_missing=""
for _tool in sed grep tr mktemp date cp wc diff find tar; do
  command -v "$_tool" >/dev/null 2>&1 || _msg_missing="$_msg_missing $_tool"
done
if [ -n "$_msg_missing" ]; then
  echo "Error: required POSIX tool(s) not found:$_msg_missing" >&2
  echo "On Windows, run mem-sync through Git Bash (Git for Windows) so its usr/bin tools are on PATH." >&2
  exit 1
fi
unset _msg_missing _tool

MEMORY_PATH=".memories"
MEMORY_ATTRS_RULE="$MEMORY_PATH/** text eol=lf"

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
REMOTE=""
REMOTE_SOURCE=""

WORKTREE_DIR="$GIT_COMMON_DIR/memories-worktree"
LOCAL_DIR="$REPO_DIR/$MEMORY_PATH"

resolve_remote() {
  # 1. explicit one-off override (never persisted)
  if [ -n "${MEM_SYNC_REMOTE:-}" ]; then
    REMOTE="$MEM_SYNC_REMOTE"
    REMOTE_SOURCE="env"
    return
  fi

  # 2. auto-detect from the repo's own push configuration
  local remotes count
  remotes="$(git -C "$REPO_DIR" remote)"
  count="$(printf '%s\n' "$remotes" | grep -c . || true)"

  if [ "$count" -eq 0 ]; then
    echo "Error: no git remote is configured for memory sync." >&2
    echo "Add one (e.g. 'git remote add origin <url>') or set MEM_SYNC_REMOTE=<name>." >&2
    exit 1
  fi

  # 2a. Honor Git's own push-remote resolution for the current branch
  #     (branch.<name>.pushRemote -> remote.pushDefault -> tracking remote).
  #     Name-independent: it follows wherever this repo actually pushes.
  #     for-each-ref's %(push:remotename) derives the destination purely from
  #     config, so it works even when the remote-tracking ref is absent locally
  #     and yields the remote name directly (no parsing). Detached HEAD -> empty.
  local br cand
  br="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -n "$br" ]; then
    cand="$(git -C "$REPO_DIR" for-each-ref --format='%(push:remotename)' "refs/heads/$br" 2>/dev/null || true)"
    if [ -n "$cand" ] && printf '%s\n' "$remotes" | grep -qx "$cand"; then
      REMOTE="$cand"
      REMOTE_SOURCE="auto-push"
      return
    fi
  fi

  # 2b. Single remote: unambiguous fallback when no push remote is configured yet.
  if [ "$count" -eq 1 ]; then
    REMOTE="$remotes"
    REMOTE_SOURCE="auto-single"
    return
  fi

  # 2c. Multiple remotes and no push target for the current branch: refuse to guess.
  echo "Error: cannot determine the memory sync remote automatically." >&2
  echo "The current branch has no push remote and several remotes exist:" >&2
  printf '%s\n' "$remotes" | sed 's/^/  - /' >&2
  echo "Set a push remote (e.g. 'git push -u <remote> <branch>')," >&2
  echo "or run a one-off: MEM_SYNC_REMOTE=<name> <command>" >&2
  exit 1
}

ensure_remote() {
  if ! git -C "$REPO_DIR" remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "Error: remote '$REMOTE' (from $REMOTE_SOURCE) does not exist but is required for memory sync." >&2
    echo "Fix it with 'git remote add $REMOTE <url>' or run 'MEM_SYNC_REMOTE=<name> <command>'." >&2
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
    printf '%s\n' "$MEMORY_ATTRS_RULE" > .gitattributes
    git add -f "$MEMORY_PATH/.gitkeep" .gitattributes
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
  # propagate_deletions=true (push): mirror local exactly, so files removed
  # locally are recorded as deletions and propagate upstream.
  # propagate_deletions=false (pull): overlay local onto the remote snapshot
  # already checked out in the worktree, so local WIP (new/modified files) is
  # preserved while files merely ABSENT locally are NOT deleted. Pull must never
  # turn an empty or partial local '.memories/' (fresh device, post-clean) into
  # an authoritative deletion of remote files.
  local propagate_deletions="${1:-true}"

  if [ ! -d "$LOCAL_DIR" ]; then
    echo "No local '$MEMORY_PATH' directory found. Only remote memories will be synced."
    return
  fi

  if [ "$propagate_deletions" = "true" ]; then
    rm -rf "${WORKTREE_DIR:?}/$MEMORY_PATH"
  fi
  mkdir -p "$WORKTREE_DIR/$MEMORY_PATH"
  cp -R "$LOCAL_DIR/." "$WORKTREE_DIR/$MEMORY_PATH/"
  # Per-device sentinel: must not propagate to other machines. On push, strip it
  # so it leaves the branch. On pull, leave the branch's copy untouched so the
  # snapshot stages no sentinel-only deletion (pull must stay a no-op when only
  # the sentinel differs); the copy-back step keeps it from reaching local.
  if [ "$propagate_deletions" = "true" ]; then
    rm -f "$WORKTREE_DIR/$MEMORY_PATH/.handoff-migrated"
  fi
  # Ensure empty subdirectories are tracked (e.g. handoffs/ with no active tasks)
  find "$WORKTREE_DIR/$MEMORY_PATH" -mindepth 1 -type d -empty -exec touch '{}/.gitkeep' \;
  touch "$WORKTREE_DIR/$MEMORY_PATH/.gitkeep"
  printf '%s\n' "$MEMORY_ATTRS_RULE" > "$WORKTREE_DIR/.gitattributes"

  git -C "$WORKTREE_DIR" -c core.safecrlf=false add -f "$MEMORY_PATH/" .gitattributes
  if git -C "$WORKTREE_DIR" diff --cached --quiet; then
    echo "No local daily log changes detected."
  else
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    git -C "$WORKTREE_DIR" commit -m "sync: local daily memories at $TIMESTAMP"
  fi
}

rebase_remote() {
  local propagate_deletions="${1:-true}"
  echo "Rebasing memory worktree with remote '$BRANCH'..."
  git -C "$WORKTREE_DIR" fetch "$REMOTE" "$BRANCH"
  if ! git -C "$WORKTREE_DIR" merge-base HEAD "$REMOTE/$BRANCH" >/dev/null 2>&1; then
    git -C "$WORKTREE_DIR" reset --hard "$REMOTE/$BRANCH"
    if [ "$propagate_deletions" = "true" ] && [ -d "$LOCAL_DIR" ]; then
      # PUSH: the branch was rewritten (e.g. a compaction's orphan commit) so we
      # cannot rebase onto it. Adopt it as the new base, then RE-APPLY this
      # device's local daily logs on top — otherwise an un-pushed local log (e.g.
      # today's) is silently discarded by the reset --hard. Overlay only (never
      # delete the adopted base's files, so other devices' logs survive) and strip
      # the per-device sentinel, matching a normal push.
      echo "Remote '$BRANCH' was rewritten (no common ancestor); adopting it as the new base and re-applying local daily logs."
      cp -R "$LOCAL_DIR/." "$WORKTREE_DIR/$MEMORY_PATH/"
      rm -f "$WORKTREE_DIR/$MEMORY_PATH/.handoff-migrated"
      find "$WORKTREE_DIR/$MEMORY_PATH" -mindepth 1 -type d -empty -exec touch '{}/.gitkeep' \;
      touch "$WORKTREE_DIR/$MEMORY_PATH/.gitkeep"
      printf '%s\n' "$MEMORY_ATTRS_RULE" > "$WORKTREE_DIR/.gitattributes"
      git -C "$WORKTREE_DIR" -c core.safecrlf=false add -f "$MEMORY_PATH/" .gitattributes
      if ! git -C "$WORKTREE_DIR" diff --cached --quiet; then
        git -C "$WORKTREE_DIR" commit -m "sync: re-apply local daily memories after adopting rewritten '$BRANCH'"
      fi
    else
      # PULL: adopt the rewrite verbatim — the compaction is authoritative,
      # including its deletions (do not resurrect locally-retained old logs).
      echo "Remote '$BRANCH' was rewritten (no common ancestor); adopting it authoritatively."
    fi
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
    # The .handoff-migrated sentinel is per-device: never import another
    # machine's copy carried on the branch, and preserve only this device's own.
    local had_migrated=false
    if [ -f "$LOCAL_DIR/.handoff-migrated" ]; then had_migrated=true; fi
    rm -rf "${LOCAL_DIR:?}"
    mkdir -p "$LOCAL_DIR"
    cp -R "$WORKTREE_DIR/$MEMORY_PATH/." "$LOCAL_DIR/"
    find "$LOCAL_DIR" -name '.gitkeep' -delete 2>/dev/null || true
    rm -f "$LOCAL_DIR/.handoff-migrated"
    if $had_migrated; then touch "$LOCAL_DIR/.handoff-migrated"; fi
  fi
}

sync_merge_remote() {
  # First arg selects deletion semantics for commit_local_snapshot:
  # push propagates local deletions; pull does not. Defaults to push.
  local propagate_deletions="${1:-true}"
  setup_worktree
  ensure_clean_worktree
  commit_local_snapshot "$propagate_deletions"
  rebase_remote "$propagate_deletions"
}

sync_push() {
  echo "Syncing local memories -> remote '$BRANCH'..."
  sync_merge_remote true
  git -C "$WORKTREE_DIR" push "$REMOTE" "$BRANCH"
  sync_back_to_local
  echo "Successfully pushed daily memories to remote."
}

sync_pull() {
  echo "Syncing remote '$BRANCH' -> local memories..."
  sync_merge_remote false
  if [ -d "$WORKTREE_DIR/$MEMORY_PATH" ]; then
    sync_back_to_local
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
  printf '%s\n' "$MEMORY_ATTRS_RULE" > "$WORKTREE_DIR/.gitattributes"
  # Rebuild history as a single orphan commit.
  # Clean up any stale compact-tmp branch left by a prior interrupted run.
  git -C "$WORKTREE_DIR" checkout "$BRANCH" >/dev/null 2>&1 || true
  git -C "$WORKTREE_DIR" branch -D "compact-tmp" >/dev/null 2>&1 || true
  git -C "$WORKTREE_DIR" checkout --orphan "compact-tmp" >/dev/null
  git -C "$WORKTREE_DIR" -c core.safecrlf=false add -Af
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

  # Surface the resolved remote/branch up front (folds in 'print-remote'), so a
  # plain status answers "which remote would a sync target?" without a 2nd call.
  if [ "$mode" = "summary" ]; then
    echo "Remote: $REMOTE ($REMOTE_SOURCE)  Branch: $BRANCH"
  fi

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

  # Exclude the .gitkeep placeholder: it stays on the branch but pull strips it
  # locally, so it would otherwise always show as a spurious remote-only diff.
  # Ignore CRLF/LF-only differences: legacy memory branches may contain CRLF
  # blobs from Windows clones before the .gitattributes rule was restored.
  if [ "$mode" = "diff" ]; then
    diff -ru --strip-trailing-cr -x '.gitkeep' -x '.handoff-migrated' "$tmp/$MEMORY_PATH" "$LOCAL_DIR" || true
    return 0
  fi

  local out
  out="$(diff -rq --strip-trailing-cr -x '.gitkeep' -x '.handoff-migrated' "$tmp/$MEMORY_PATH" "$LOCAL_DIR" 2>/dev/null || true)"
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
    resolve_remote
    sync_push
    ;;
  pull)
    resolve_remote
    sync_pull
    ;;
  compact)
    resolve_remote
    sync_compact
    ;;
  status)
    resolve_remote
    sync_status summary
    ;;
  diff)
    resolve_remote
    sync_status diff
    ;;
  print-branch)
    printf '%s\n' "$BRANCH"
    ;;
  print-remote)
    resolve_remote
    printf '%s\n' "$REMOTE"
    ;;
  *)
    echo "Usage: $0 {push|pull|compact|status|diff|print-branch|print-remote}"
    exit 1
    ;;
esac
