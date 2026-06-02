#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SOURCE="$ROOT_DIR/skills/memory/scripts/sync-memory.sh"

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

  mkdir -p "$repo/skills/memory/scripts"
  cp "$SCRIPT_SOURCE" "$repo/skills/memory/scripts/sync-memory.sh"
  chmod +x "$repo/skills/memory/scripts/sync-memory.sh"
}

run_sync() {
  local repo="$1"
  local command="$2"

  (
    cd "$repo"
    ./skills/memory/scripts/sync-memory.sh "$command"
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

main() {
  test_push_merges_remote_same_file_when_local_has_no_new_changes
  test_pull_preserves_local_wip_and_merges_remote_changes
  echo "sync-memory integration tests passed"
}

main "$@"
