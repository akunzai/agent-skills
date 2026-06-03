#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SOURCE="$ROOT_DIR/skills/mem-sync/scripts/mem-sync-git.sh"

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "Expected '$file' to contain: $expected" >&2
    echo "Actual contents:" >&2
    sed -n '1,120p' "$file" >&2 || true
    return 1
  fi
}

copy_sync_script() {
  local repo="$1"

  mkdir -p "$repo/skills/mem-sync/scripts"
  cp "$SCRIPT_SOURCE" "$repo/skills/mem-sync/scripts/mem-sync-git.sh"
  chmod +x "$repo/skills/mem-sync/scripts/mem-sync-git.sh"
}

run_sync() {
  local repo="$1"
  local command="$2"

  (
    cd "$repo"
    ./skills/mem-sync/scripts/mem-sync-git.sh "$command"
  )
}

init_origin_with_clone() {
  local tmp="$1"
  local origin="$tmp/origin.git"
  local repo="$tmp/repo-a"

  git init --bare "$origin" >/dev/null
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  git clone "$origin" "$repo" >/dev/null 2>&1
  (
    cd "$repo"
    git config user.email "memory-test@example.com"
    git config user.name "Memory Test"
    echo "# Test Repo" > README.md
    git add README.md
    git commit -m "Initial commit" >/dev/null
    git push origin HEAD:main >/dev/null 2>&1
  )

  copy_sync_script "$repo"
  printf '%s\n' "$repo"
}

clone_repo() {
  local origin="$1"
  local repo="$2"

  git clone --branch main "$origin" "$repo" >/dev/null 2>&1
  (
    cd "$repo"
    git config user.email "memory-test@example.com"
    git config user.name "Memory Test"
  )
  copy_sync_script "$repo"
}

test_push_merges_remote_same_file_when_local_has_no_new_changes() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "base" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  run_sync "$repo_b" pull >/dev/null

  printf '%s\n' "base" "remote-only" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  run_sync "$repo_b" push >/dev/null

  assert_contains "$repo_b/.memories/2026-06-02.md" "remote-only"

  local verify="$tmp/verify"
  clone_repo "$origin" "$verify"
  run_sync "$verify" pull >/dev/null
  assert_contains "$verify/.memories/2026-06-02.md" "remote-only"
}

test_pull_preserves_local_wip_and_merges_remote_changes() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "local-slot: empty" "shared" "remote-slot: empty" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  run_sync "$repo_b" pull >/dev/null

  printf '%s\n' "local-slot: local-wip" "shared" "remote-slot: empty" > "$repo_b/.memories/2026-06-02.md"
  printf '%s\n' "local-slot: empty" "shared" "remote-slot: remote-update" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  run_sync "$repo_b" pull >/dev/null

  assert_contains "$repo_b/.memories/2026-06-02.md" "local-wip"
  assert_contains "$repo_b/.memories/2026-06-02.md" "remote-update"
}

test_compact_rewrite_is_adopted_without_resurrecting_deletes() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  # Two dated logs exist on both devices.
  mkdir -p "$repo_a/.memories"
  printf '%s\n' "old" > "$repo_a/.memories/2026-01-01.md"
  printf '%s\n' "keep" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null
  run_sync "$repo_b" pull >/dev/null
  assert_contains "$repo_b/.memories/2026-01-01.md" "old"

  # Device A "cleans": delete the expired log locally, then authoritative rewrite.
  rm "$repo_a/.memories/2026-01-01.md"
  run_sync "$repo_a" compact >/dev/null

  # Device B syncs: must adopt the rewrite, not resurrect the deleted log.
  run_sync "$repo_b" pull >/dev/null
  if [ -e "$repo_b/.memories/2026-01-01.md" ]; then
    echo "FAIL: deleted log resurrected on device B after compact" >&2
    return 1
  fi
  assert_contains "$repo_b/.memories/2026-06-02.md" "keep"

  # And device B pushing back must not re-add it to origin.
  run_sync "$repo_b" push >/dev/null
  local verify="$tmp/verify"
  clone_repo "$origin" "$verify"
  run_sync "$verify" pull >/dev/null
  if [ -e "$verify/.memories/2026-01-01.md" ]; then
    echo "FAIL: deleted log resurrected in origin after device B push" >&2
    return 1
  fi
}

test_compact_is_rerunnable_after_interrupted_run() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  # First compact succeeds normally.
  mkdir -p "$repo_a/.memories"
  printf '%s\n' "v1" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" compact >/dev/null

  # Simulate an interrupted prior run leaving compact-tmp behind.
  local wt="$repo_a/.git/memories-worktree"
  git -C "$wt" branch compact-tmp >/dev/null 2>&1 || true

  # Second compact MUST succeed (regression: before the fix this fails with exit 128).
  printf '%s\n' "v2" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" compact >/dev/null

  # Assert the second compact's content reached origin.
  local verify="$tmp/verify"
  clone_repo "$origin" "$verify"
  run_sync "$verify" pull >/dev/null
  assert_contains "$verify/.memories/2026-06-02.md" "v2"
}

test_push_respects_overridden_remote() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  # A separate remote the user wants memory to go to instead of origin.
  local private="$tmp/private.git"
  git init --bare "$private" >/dev/null
  git -C "$repo_a" remote add private "$private"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  (
    cd "$repo_a"
    MEM_SYNC_REMOTE=private ./skills/mem-sync/scripts/mem-sync-git.sh push >/dev/null
  )

  # The per-user branch must land on the overridden remote...
  if ! git ls-remote --heads "$private" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: branch was not pushed to overridden remote 'private'" >&2
    return 1
  fi
  # ...and must NOT leak to the default origin.
  if git ls-remote --heads "$origin" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: branch leaked to default 'origin' despite MEM_SYNC_REMOTE override" >&2
    return 1
  fi
}

test_status_and_diff_report_local_vs_remote() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local script="./skills/mem-sync/scripts/mem-sync-git.sh"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "base" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  # After push, local matches remote -> status reports in sync.
  local s
  s="$(cd "$repo_a" && "$script" status)"
  case "$s" in
    *"In sync"*) ;;
    *) echo "FAIL: status should report in sync after push; got: $s" >&2; return 1 ;;
  esac

  # No argument must default to 'status' and not error under set -u.
  local s0
  s0="$(cd "$repo_a" && "$script")"
  case "$s0" in
    *"In sync"*) ;;
    *) echo "FAIL: no-arg invocation should default to status; got: $s0" >&2; return 1 ;;
  esac

  # Diverge locally: modify one file, add a new one.
  printf '%s\n' "base" "changed" > "$repo_a/.memories/2026-06-02.md"
  printf '%s\n' "fresh" > "$repo_a/.memories/2026-06-03.md"

  s="$(cd "$repo_a" && "$script" status)"
  case "$s" in
    *"In sync"*) echo "FAIL: status should report differences after local edits; got: $s" >&2; return 1 ;;
  esac
  case "$s" in
    *2026-06-03.md*) ;;
    *) echo "FAIL: status should flag local-only 2026-06-03.md; got: $s" >&2; return 1 ;;
  esac
  case "$s" in
    *2026-06-02.md*) ;;
    *) echo "FAIL: status should flag modified 2026-06-02.md; got: $s" >&2; return 1 ;;
  esac

  # diff shows the modified content.
  local d
  d="$(cd "$repo_a" && "$script" diff)"
  case "$d" in
    *changed*) ;;
    *) echo "FAIL: diff should show modified content 'changed'; got: $d" >&2; return 1 ;;
  esac
}

main() {
  test_push_merges_remote_same_file_when_local_has_no_new_changes
  test_pull_preserves_local_wip_and_merges_remote_changes
  test_compact_rewrite_is_adopted_without_resurrecting_deletes
  test_compact_is_rerunnable_after_interrupted_run
  test_push_respects_overridden_remote
  test_status_and_diff_report_local_vs_remote
  echo "git-sync-memory integration tests passed"
}

main "$@"
