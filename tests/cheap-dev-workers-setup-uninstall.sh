#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"

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
if HOME="$fake_home" bash "$PLUGIN_DIR/scripts/setup.sh" --dest "$dest" >/dev/null 2>&1; then
  fail "setup.sh should reject the removed --dest flag"
fi
[ ! -d "$dest" ] || fail "setup.sh must not create $dest when it rejects an unknown argument"

# --- setup refuses to overwrite an independently owned role ---
mkdir -p "$dest"
printf 'user-owned\n' >"$dest/check-runner.toml"
if HOME="$fake_home" bash "$PLUGIN_DIR/scripts/setup.sh" >/dev/null 2>&1; then
  fail "setup.sh should refuse a conflicting personal agent"
fi
grep -q 'user-owned' "$dest/check-runner.toml" || fail "setup.sh overwrote a conflicting agent"
[[ ! -e "$dest/repo-explorer.toml" ]] || fail "setup.sh partially installed before conflict"
rm "$dest/check-runner.toml"

# --- setup.sh installs all four agents, byte-identical to the plugin source ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/setup.sh" >/dev/null

for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ -f "$dest/$name" ] || fail "setup.sh did not install $name into $dest"
  diff -q "$PLUGIN_DIR/codex-agents/$name" "$dest/$name" >/dev/null \
    || fail "$dest/$name differs from the plugin source $name"
done

# --- uninstall refuses a locally modified installed role ---
printf '\n# local change\n' >>"$dest/check-runner.toml"
if HOME="$fake_home" bash "$PLUGIN_DIR/scripts/uninstall.sh" >/dev/null 2>&1; then
  fail "uninstall.sh should refuse a modified installed agent"
fi
[[ -f "$dest/check-runner.toml" ]] || fail "uninstall.sh removed a modified agent"
[[ -f "$dest/repo-explorer.toml" ]] || fail "uninstall.sh partially removed before conflict"
cp "$PLUGIN_DIR/codex-agents/check-runner.toml" "$dest/check-runner.toml"

# --- uninstall.sh removes exactly what setup.sh installed ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/uninstall.sh" >/dev/null

for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ ! -f "$dest/$name" ] || fail "uninstall.sh left $dest/$name behind"
done
# --- uninstall.sh on an already-empty destination is a no-op, not an error ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/uninstall.sh" >/dev/null \
  || fail "uninstall.sh must succeed even when nothing is installed"

echo "cheap-dev-workers setup/uninstall checks passed"
