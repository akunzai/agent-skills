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

assert_eq_str() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: ${3:-assertion}: expected '$2' but got '$1'" >&2
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

test_push_propagates_file_deletion() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "keep" > "$repo_a/.memories/2026-06-02.md"
  printf '%s\n' "delete me" > "$repo_a/.memories/2026-06-03.md"
  run_sync "$repo_a" push >/dev/null

  run_sync "$repo_b" pull >/dev/null
  assert_contains "$repo_b/.memories/2026-06-03.md" "delete me"

  # Device A deletes a file and pushes.
  rm "$repo_a/.memories/2026-06-03.md"
  run_sync "$repo_a" push >/dev/null

  # The deleted file must not come back to device A's local dir.
  if [ -e "$repo_a/.memories/2026-06-03.md" ]; then
    echo "FAIL: deleted file resurrected on device A after push" >&2
    return 1
  fi

  # Device B pulls: deleted file must be gone.
  run_sync "$repo_b" pull >/dev/null
  if [ -e "$repo_b/.memories/2026-06-03.md" ]; then
    echo "FAIL: deleted file resurrected on device B after push+pull" >&2
    return 1
  fi
  assert_contains "$repo_b/.memories/2026-06-02.md" "keep"

  # Verify the deletion is on origin too.
  local verify="$tmp/verify"
  clone_repo "$origin" "$verify"
  run_sync "$verify" pull >/dev/null
  if [ -e "$verify/.memories/2026-06-03.md" ]; then
    echo "FAIL: deleted file still present on origin after push" >&2
    return 1
  fi
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

test_auto_picks_non_origin_and_persists() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  # A second, writable remote (the user's fork).
  local fork="$tmp/fork.git"
  git init --bare "$fork" >/dev/null
  git -C "$repo_a" remote add fork "$fork"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  # Non-origin remote selected: branch lands on fork, not origin.
  if ! git ls-remote --heads "$fork" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: auto-pick did not push to non-origin remote 'fork'" >&2
    return 1
  fi
  if git ls-remote --heads "$origin" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: branch leaked to 'origin' despite non-origin auto-pick" >&2
    return 1
  fi
  # The successful auto-pick is persisted to per-repo config.
  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote || true)"
  assert_eq_str "$cfg" "fork" "memsync.remote should be persisted as 'fork'"
}

test_single_remote_auto_detect_not_persisted() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote 2>/dev/null || true)"
  assert_eq_str "$cfg" "" "single-remote auto-detect must not persist memsync.remote"
}

test_ambiguous_remotes_abort_without_config() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"

  # origin + two more remotes => >2 total => ambiguous.
  local f1="$tmp/f1.git" f2="$tmp/f2.git"
  git init --bare "$f1" >/dev/null
  git init --bare "$f2" >/dev/null
  git -C "$repo_a" remote add fork1 "$f1"
  git -C "$repo_a" remote add fork2 "$f2"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  if (cd "$repo_a" && ./skills/mem-sync/scripts/mem-sync-git.sh push >/dev/null 2>&1); then
    echo "FAIL: ambiguous remote set should abort push" >&2
    return 1
  fi
  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote 2>/dev/null || true)"
  assert_eq_str "$cfg" "" "ambiguous abort must not write memsync.remote"
}

test_config_remote_used_over_autodetect() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  # origin + chosen would auto-pick 'chosen'; config naming origin must win.
  local chosen="$tmp/chosen.git"
  git init --bare "$chosen" >/dev/null
  git -C "$repo_a" remote add chosen "$chosen"
  git -C "$repo_a" config --local memsync.remote origin

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  if ! git ls-remote --heads "$origin" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: config-named remote 'origin' was not used" >&2
    return 1
  fi
  if git ls-remote --heads "$chosen" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: auto-pick overrode explicit config" >&2
    return 1
  fi
  # config-sourced remotes are not rewritten by persist.
  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote || true)"
  assert_eq_str "$cfg" "origin" "config remote must remain unchanged"
}

test_env_overrides_persisted_config() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"

  local envremote="$tmp/envr.git" cfgremote="$tmp/cfgr.git"
  git init --bare "$envremote" >/dev/null
  git init --bare "$cfgremote" >/dev/null
  git -C "$repo_a" remote add envr "$envremote"
  git -C "$repo_a" remote add cfgr "$cfgremote"
  git -C "$repo_a" config --local memsync.remote cfgr

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  (cd "$repo_a" && MEM_SYNC_REMOTE=envr ./skills/mem-sync/scripts/mem-sync-git.sh push >/dev/null)

  if ! git ls-remote --heads "$envremote" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: env remote 'envr' not used" >&2
    return 1
  fi
  if git ls-remote --heads "$cfgremote" memories/memory-test | grep -q memories/memory-test; then
    echo "FAIL: config remote used despite env override" >&2
    return 1
  fi
  # env is one-off: persisted config value is untouched.
  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote || true)"
  assert_eq_str "$cfg" "cfgr" "env override must not overwrite memsync.remote"
}

test_status_does_not_persist_autopick() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"

  local fork="$tmp/fork.git"
  git init --bare "$fork" >/dev/null
  git -C "$repo_a" remote add fork "$fork"

  # status auto-picks 'fork' but is read-only and must not write config.
  (cd "$repo_a" && ./skills/mem-sync/scripts/mem-sync-git.sh status >/dev/null 2>&1) || true

  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote 2>/dev/null || true)"
  assert_eq_str "$cfg" "" "read-only status must not persist memsync.remote"
}

test_print_remote_reports_resolved_remote() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local script="./skills/mem-sync/scripts/mem-sync-git.sh"

  # Single remote: print-remote reports it (read-only, no config written).
  local r
  r="$(cd "$repo_a" && "$script" print-remote)"
  assert_eq_str "$r" "origin" "print-remote should report the single remote"
  local cfg
  cfg="$(git -C "$repo_a" config --local memsync.remote 2>/dev/null || true)"
  assert_eq_str "$cfg" "" "print-remote must not persist memsync.remote"

  # origin + fork: print-remote reports the non-origin auto-pick.
  local fork="$tmp/fork.git"
  git init --bare "$fork" >/dev/null
  git -C "$repo_a" remote add fork "$fork"
  r="$(cd "$repo_a" && "$script" print-remote)"
  assert_eq_str "$r" "fork" "print-remote should report the auto-picked non-origin remote"

  # env override wins.
  r="$(cd "$repo_a" && MEM_SYNC_REMOTE=origin "$script" print-remote)"
  assert_eq_str "$r" "origin" "print-remote should honor MEM_SYNC_REMOTE"

  # Ambiguous remote set: print-remote exits non-zero.
  local f2="$tmp/f2.git"
  git init --bare "$f2" >/dev/null
  git -C "$repo_a" remote add fork2 "$f2"
  if (cd "$repo_a" && "$script" print-remote >/dev/null 2>&1); then
    echo "FAIL: print-remote should abort on an ambiguous remote set" >&2
    return 1
  fi
}

test_gitattributes_enforces_lf_on_push() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  local attrs
  attrs="$(git -C "$origin" archive "memories/memory-test" -- ".gitattributes" 2>/dev/null | tar -xO -f - ".gitattributes" 2>/dev/null || true)"
  case "$attrs" in
    *".memories/** text eol=lf"*) ;;
    *) echo "FAIL: memory branch .gitattributes missing eol=lf rule; got: $attrs" >&2; return 1 ;;
  esac
}

test_gitattributes_survives_compact() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  # Simulate a legacy memory branch created before the eol=lf rule: drop
  # .gitattributes and commit its removal in the worktree, so compact must
  # re-establish it rather than merely inherit it from create_memory_branch.
  local wt="$repo_a/.git/memories-worktree"
  git -C "$wt" rm -q .gitattributes
  git -C "$wt" commit -q -m "legacy: drop eol=lf rule"

  run_sync "$repo_a" compact >/dev/null

  local attrs
  attrs="$(git -C "$origin" archive "memories/memory-test" -- ".gitattributes" 2>/dev/null | tar -xO -f - ".gitattributes" 2>/dev/null || true)"
  case "$attrs" in
    *".memories/** text eol=lf"*) ;;
    *) echo "FAIL: .gitattributes lost after compact; got: $attrs" >&2; return 1 ;;
  esac
}

test_push_restores_missing_gitattributes() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"

  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  local wt="$repo_a/.git/memories-worktree"
  git -C "$wt" rm -q .gitattributes
  git -C "$wt" commit -q -m "legacy: drop eol=lf rule"
  git -C "$wt" push -q origin memories/memory-test

  printf '%s\n' "second note" > "$repo_a/.memories/2026-06-03.md"
  run_sync "$repo_a" push >/dev/null

  local attrs
  attrs="$(git -C "$origin" archive "memories/memory-test" -- ".gitattributes" 2>/dev/null | tar -xO -f - ".gitattributes" 2>/dev/null || true)"
  case "$attrs" in
    *".memories/** text eol=lf"*) ;;
    *) echo "FAIL: push did not restore .gitattributes; got: $attrs" >&2; return 1 ;;
  esac
}

test_status_in_sync_ignores_gitkeep_after_pull() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  # Device A pushes a daily log; the branch also carries a .gitkeep placeholder.
  mkdir -p "$repo_a/.memories"
  printf '%s\n' "note" > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  # Device B pulls; pull strips the local .gitkeep while it stays on the branch.
  run_sync "$repo_b" pull >/dev/null

  # status must report in sync and must NOT flag the .gitkeep placeholder.
  local s
  s="$(cd "$repo_b" && ./skills/mem-sync/scripts/mem-sync-git.sh status)"
  case "$s" in
    *.gitkeep*) echo "FAIL: status leaked .gitkeep placeholder; got: $s" >&2; return 1 ;;
  esac
  case "$s" in
    *"In sync"*) ;;
    *) echo "FAIL: status should report in sync after pull; got: $s" >&2; return 1 ;;
  esac
}

test_status_ignores_crlf_lf_only_differences() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"

  mkdir -p "$repo_a/.memories"
  printf 'line one\r\nline two\r\n' > "$repo_a/.memories/2026-06-02.md"
  run_sync "$repo_a" push >/dev/null

  printf 'line one\nline two\n' > "$repo_a/.memories/2026-06-02.md"

  local s
  s="$(cd "$repo_a" && ./skills/mem-sync/scripts/mem-sync-git.sh status)"
  case "$s" in
    *"In sync"*) ;;
    *) echo "FAIL: status should ignore CRLF/LF-only differences; got: $s" >&2; return 1 ;;
  esac

  local d
  d="$(cd "$repo_a" && ./skills/mem-sync/scripts/mem-sync-git.sh diff)"
  [ -z "$d" ] || {
    echo "FAIL: diff should ignore CRLF/LF-only differences; got: $d" >&2
    return 1
  }
}

test_push_syncs_back_remote_deletion_to_local() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local repo_a
  repo_a="$(init_origin_with_clone "$tmp")"
  local origin="$tmp/origin.git"
  local repo_b="$tmp/repo-b"
  clone_repo "$origin" "$repo_b"

  # Device A pushes two files; device B pulls both.
  mkdir -p "$repo_a/.memories"
  printf '%s\n' "keep" > "$repo_a/.memories/2026-06-02.md"
  printf '%s\n' "gone" > "$repo_a/.memories/2026-06-03.md"
  run_sync "$repo_a" push >/dev/null
  run_sync "$repo_b" pull >/dev/null
  assert_contains "$repo_b/.memories/2026-06-03.md" "gone"

  # Device A deletes one file and pushes.
  rm "$repo_a/.memories/2026-06-03.md"
  run_sync "$repo_a" push >/dev/null

  # Device B still has the file locally and has not pulled the deletion yet.
  assert_contains "$repo_b/.memories/2026-06-03.md" "gone"

  # Device B pushes: rebase incorporates A's deletion; sync_back_to_local must
  # apply the merged result so the deleted file disappears from B's local dir.
  run_sync "$repo_b" push >/dev/null
  if [ -e "$repo_b/.memories/2026-06-03.md" ]; then
    echo "FAIL: deleted file survived in device B local after push absorbed remote deletion" >&2
    return 1
  fi
  assert_contains "$repo_b/.memories/2026-06-02.md" "keep"
}

main() {
  test_push_propagates_file_deletion
  test_push_syncs_back_remote_deletion_to_local
  test_push_merges_remote_same_file_when_local_has_no_new_changes
  test_pull_preserves_local_wip_and_merges_remote_changes
  test_compact_rewrite_is_adopted_without_resurrecting_deletes
  test_compact_is_rerunnable_after_interrupted_run
  test_push_respects_overridden_remote
  test_status_and_diff_report_local_vs_remote
  test_auto_picks_non_origin_and_persists
  test_single_remote_auto_detect_not_persisted
  test_ambiguous_remotes_abort_without_config
  test_config_remote_used_over_autodetect
  test_env_overrides_persisted_config
  test_status_does_not_persist_autopick
  test_print_remote_reports_resolved_remote
  test_gitattributes_enforces_lf_on_push
  test_gitattributes_survives_compact
  test_push_restores_missing_gitattributes
  test_status_in_sync_ignores_gitkeep_after_pull
  test_status_ignores_crlf_lf_only_differences
  echo "git-sync-memory integration tests passed"
}

main "$@"
