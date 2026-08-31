#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"

fail() {
  echo "cheap-dev-workers upgrade check failed: $*" >&2
  exit 1
}

fake_home="$(mktemp -d)"
cleanup() {
  rm -rf "$fake_home"
}
trap cleanup EXIT

dest="$fake_home/.codex/agents"

# --- unknown argument is rejected ---
if HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --invalid-arg >/dev/null 2>&1; then
  fail "upgrade.sh should reject unknown argument"
fi

# --- invalid scope is rejected ---
if HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --scope invalid >/dev/null 2>&1; then
  fail "upgrade.sh should reject invalid scope"
fi

# --- help option works ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --help >/dev/null \
  || fail "upgrade.sh --help failed"

# --- check mode does not create missing directories ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --codex-only --check >/dev/null \
  || fail "upgrade.sh --check failed"
[ ! -d "$dest" ] || fail "upgrade.sh --check should not create $dest"

# --- upgrade installs all 4 agents into destination ---
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --codex-only >/dev/null \
  || fail "upgrade.sh --codex-only failed"

for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ -f "$dest/$name" ] || fail "upgrade.sh did not install $name into $dest"
  diff -q "$PLUGIN_DIR/codex-agents/$name" "$dest/$name" >/dev/null \
    || fail "$dest/$name differs from the plugin source $name"
done

# --- upgrade safely overwrites existing older/differing agent definitions ---
printf 'old-version\n' >"$dest/check-runner.toml"
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/upgrade.sh" --codex-only >/dev/null \
  || fail "upgrade.sh failed when updating existing agent"
diff -q "$PLUGIN_DIR/codex-agents/check-runner.toml" "$dest/check-runner.toml" >/dev/null \
  || fail "upgrade.sh did not overwrite old agent"

echo "cheap-dev-workers upgrade checks passed"
