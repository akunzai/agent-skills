#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"
INSTALL_SCRIPT="$PLUGIN_DIR/scripts/install-codex-agents.sh"
REMOVE_SCRIPT="$PLUGIN_DIR/scripts/uninstall-codex-agents.sh"

fail() {
  echo "cheap-dev-workers setup/uninstall check failed: $*" >&2
  exit 1
}

fake_home="$(mktemp -d)"
cleanup() {
  rm -rf "$fake_home"
}
trap cleanup EXIT

dest="$fake_home/.codex/agents"

# --- unknown argument is rejected, does not touch the filesystem ---
if HOME="$fake_home" bash "$INSTALL_SCRIPT" --dest "$dest" >/dev/null 2>&1; then
  fail "install helper should reject the removed --dest flag"
fi
[ ! -d "$dest" ] || fail "install helper must not create $dest when it rejects an unknown argument"

# --- setup refuses to overwrite an independently owned role ---
mkdir -p "$dest"
printf 'user-owned\n' >"$dest/check-runner.toml"
if HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1; then
  fail "install helper should refuse a conflicting personal agent"
fi
grep -q 'user-owned' "$dest/check-runner.toml" || fail "install helper overwrote a conflicting agent"
[[ ! -e "$dest/repo-explorer.toml" ]] || fail "install helper partially installed before conflict"
rm "$dest/check-runner.toml"

# --- install helper installs all four agents, byte-identical to the source ---
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null

for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ -f "$dest/$name" ] || fail "install helper did not install $name into $dest"
  diff -q "$PLUGIN_DIR/codex-agents/$name" "$dest/$name" >/dev/null \
    || fail "$dest/$name differs from the plugin source $name"
done

# --- uninstall refuses a locally modified installed role ---
printf '\n# local change\n' >>"$dest/check-runner.toml"
if HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null 2>&1; then
  fail "remove helper should refuse a modified installed agent"
fi
[[ -f "$dest/check-runner.toml" ]] || fail "remove helper removed a modified agent"
[[ -f "$dest/repo-explorer.toml" ]] || fail "remove helper partially removed before conflict"
cp "$PLUGIN_DIR/codex-agents/check-runner.toml" "$dest/check-runner.toml"

# --- remove helper removes exactly what the install helper installed ---
HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null

for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ ! -f "$dest/$name" ] || fail "remove helper left $dest/$name behind"
done
# --- remove helper on an already-empty destination is a no-op, not an error ---
HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null \
  || fail "remove helper must succeed even when nothing is installed"

echo "cheap-dev-workers setup/uninstall checks passed"
