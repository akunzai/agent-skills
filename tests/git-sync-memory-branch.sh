#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/mem-sync/scripts/mem-sync-git.sh"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

derive() {
  local email="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN
  (
    cd "$tmp"
    git init -q
    git config user.email "$email"
    git config user.name "Test"
    "$SCRIPT" print-branch
  )
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: expected '$2' but got '$1'" >&2
    exit 1
  fi
}

assert_eq "$(derive 'User@Example.com')" "memories/user"
assert_eq "$(derive 'memory-test@example.com')" "memories/memory-test"
assert_eq "$(derive 'john.doe+tag@example.com')" "memories/john-doe-tag"

# unset email must abort non-zero
tmp="$(mktemp -d)"
(
  cd "$tmp"
  git init -q
  git config --unset user.email 2>/dev/null || true
)
if (cd "$tmp" && "$SCRIPT" print-branch >/dev/null 2>&1); then
  echo "FAIL: expected non-zero exit when user.email is unset" >&2
  rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"

echo "git-sync-memory branch derivation tests passed"
