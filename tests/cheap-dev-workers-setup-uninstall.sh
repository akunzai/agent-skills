#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"
RELEASED_COMMIT_WRITER="$ROOT_DIR/tests/fixtures/cheap-dev-workers/commit-writer-released.toml"
RELEASED_CHECK_RUNNER="$ROOT_DIR/tests/fixtures/cheap-dev-workers/check-runner-released.toml"
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
printf 'user-owned\n' >"$dest/log-summarizer.toml"
if HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1; then
  fail "install helper should refuse a conflicting personal agent"
fi
grep -q 'user-owned' "$dest/log-summarizer.toml" || fail "install helper overwrote a conflicting agent"
[[ ! -e "$dest/repo-explorer.toml" ]] || fail "install helper partially installed before conflict"
rm "$dest/log-summarizer.toml"

# --- a modified released agent blocks the whole sync ---
cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/log-summarizer-released.toml" "$dest/log-summarizer.toml"
printf '\n# local change\n' >>"$dest/log-summarizer.toml"
cp "$dest/log-summarizer.toml" "$fake_home/modified.toml"
if HOME="$fake_home" bash "$INSTALL_SCRIPT" >"$fake_home/conflict.log" 2>&1; then
  fail "install helper should refuse a modified released agent"
fi
cmp -s "$fake_home/modified.toml" "$dest/log-summarizer.toml" \
  || fail "install helper changed a modified released agent"
[[ ! -e "$dest/repo-explorer.toml" ]] || fail "install helper partially upgraded before conflict"
grep -q 'modified or unknown agent' "$fake_home/conflict.log" \
  || fail "conflict message did not explain the ownership uncertainty"

# --- released agents upgrade from a plugin snapshot without Git metadata ---
for role in repo-explorer log-summarizer; do
  cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/$role-released.toml" "$dest/$role.toml"
done
snapshot="$fake_home/plugin"
mkdir -p "$snapshot"
cp -R "$PLUGIN_DIR/scripts" "$PLUGIN_DIR/codex-agents" "$snapshot/"
HOME="$fake_home" bash "$snapshot/scripts/install-codex-agents.sh" >/dev/null \
  || fail "install helper refused unmodified released agents"

for role in repo-explorer log-summarizer; do
  cmp -s "$PLUGIN_DIR/codex-agents/$role.toml" "$dest/$role.toml" \
    || fail "snapshot install did not upgrade $role to the current definition"
done

# --- install helper installs every agent, byte-identical to the source ---
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null

for name in repo-explorer.toml evidence-collector.toml log-summarizer.toml; do
  [ -f "$dest/$name" ] || fail "install helper did not install $name into $dest"
  diff -q "$PLUGIN_DIR/codex-agents/$name" "$dest/$name" >/dev/null \
    || fail "$dest/$name differs from the plugin source $name"
done
[ ! -e "$dest/commit-writer.toml" ] \
  || fail "install helper must not install leftover commit-writer.toml"

# --- keep current release fingerprints for the next upgrade ---
for name in repo-explorer.toml evidence-collector.toml log-summarizer.toml; do
  digest="$(shasum -a 256 "$PLUGIN_DIR/codex-agents/$name" | cut -d' ' -f1)"
  grep -Fqx "$name $digest" "$PLUGIN_DIR/scripts/released-codex-agents.sha256" \
    || fail "record the release fingerprint for $name before shipping it"
done

# --- a modified retired commit-writer is preserved without blocking sync ---
cp "$RELEASED_COMMIT_WRITER" "$dest/commit-writer.toml"
printf '\n# local change\n' >>"$dest/commit-writer.toml"
cp "$dest/commit-writer.toml" "$fake_home/modified-commit-writer.toml"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1 \
  || fail "a modified retired commit-writer must not fail the install"
cmp -s "$fake_home/modified-commit-writer.toml" "$dest/commit-writer.toml" \
  || fail "install removed or changed a modified commit-writer"
HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null 2>&1 \
  || fail "a modified retired commit-writer must not fail uninstall"
cmp -s "$fake_home/modified-commit-writer.toml" "$dest/commit-writer.toml" \
  || fail "uninstall removed or changed a modified commit-writer"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1
printf 'user-owned\n' >"$dest/commit-writer.toml"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1
grep -qx 'user-owned' "$dest/commit-writer.toml" \
  || fail "install removed an unknown commit-writer"

# --- leftover commit-writer.toml from older installs is removed ---
cp "$RELEASED_COMMIT_WRITER" "$dest/commit-writer.toml"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null
[ ! -e "$dest/commit-writer.toml" ] \
  || fail "install helper left leftover commit-writer.toml in place"

# --- a released check-runner.toml is retired; an edited one is kept ---
cp "$RELEASED_CHECK_RUNNER" "$dest/check-runner.toml"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null
[ ! -e "$dest/check-runner.toml" ] \
  || fail "install helper left a released check-runner.toml in place"
printf 'user-owned\n' >"$dest/check-runner.toml"
HOME="$fake_home" bash "$INSTALL_SCRIPT" >/dev/null 2>&1 \
  || fail "an edited check-runner.toml must not fail the install"
grep -q 'user-owned' "$dest/check-runner.toml" \
  || fail "install helper removed an edited check-runner.toml"
rm "$dest/check-runner.toml"

# --- the retire helper also runs on its own, defaulting to ~/.codex/agents ---
cp "$RELEASED_CHECK_RUNNER" "$dest/check-runner.toml"
HOME="$fake_home" bash "$PLUGIN_DIR/scripts/retired-codex-agents.sh" >/dev/null \
  || fail "retire helper without an argument must succeed when it removes a file"
[ ! -e "$dest/check-runner.toml" ] \
  || fail "retire helper without an argument left a released check-runner.toml"

# --- uninstall refuses a locally modified installed role ---
printf '\n# local change\n' >>"$dest/log-summarizer.toml"
if HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null 2>&1; then
  fail "remove helper should refuse a modified installed agent"
fi
[[ -f "$dest/log-summarizer.toml" ]] || fail "remove helper removed a modified agent"
[[ -f "$dest/repo-explorer.toml" ]] || fail "remove helper partially removed before conflict"
cp "$PLUGIN_DIR/codex-agents/log-summarizer.toml" "$dest/log-summarizer.toml"

# --- remove helper removes exactly what the install helper installed,
#     plus retired agents from earlier releases ---
cp "$RELEASED_COMMIT_WRITER" "$dest/commit-writer.toml"
cp "$RELEASED_CHECK_RUNNER" "$dest/check-runner.toml"
HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null

for name in repo-explorer.toml evidence-collector.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ ! -f "$dest/$name" ] || fail "remove helper left $dest/$name behind"
done
# --- remove helper on an already-empty destination is a no-op, not an error ---
HOME="$fake_home" bash "$REMOVE_SCRIPT" >/dev/null \
  || fail "remove helper must succeed even when nothing is installed"

echo "cheap-dev-workers setup/uninstall checks passed"
