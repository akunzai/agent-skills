#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/setup.sh"

fail() {
  echo "plugin setup check failed: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

for script in setup.sh upgrade.sh uninstall.sh manage-plugins.sh; do
  [ -x "$ROOT_DIR/scripts/$script" ] \
    || fail "scripts/$script is missing or not executable"
done

# The repository-level lifecycle scripts are the only public entry points.
# Plugin directories may contain internal helpers, but no compatibility
# setup/upgrade/uninstall wrappers.
for plugin in cheap-dev-workers codexbar-quota-handoff; do
  for script in setup.sh upgrade.sh uninstall.sh; do
    [ ! -e "$ROOT_DIR/plugins/$plugin/scripts/$script" ] \
      || fail "plugins/$plugin/scripts/$script must not be a public lifecycle entry point"
  done
done

if bash "$ROOT_DIR/scripts/setup.sh" --keep-state >/dev/null 2>&1; then
  fail "setup accepted uninstall-only --keep-state"
fi
if bash "$ROOT_DIR/scripts/uninstall.sh" --threshold 0.8 >/dev/null 2>&1; then
  fail "uninstall accepted install/upgrade-only --threshold"
fi
if bash "$ROOT_DIR/scripts/setup.sh" --threshold invalid >/dev/null 2>&1; then
  fail "setup accepted an invalid CodexBar threshold"
fi

# --- an empty ${compatible_plugins[@]} (no marketplace plugin supported by
# the selected runtime) crashed macOS's stock /bin/bash 3.2 under `set -u`
# at `plugins=("${compatible_plugins[@]}")`; exercise that path explicitly
# under it with a fixture repo root whose Codex marketplace lists none of
# the plugins the Claude-side manifest carries. ---
mp_fixture="$tmp_dir/mp-fixture"
mkdir -p "$mp_fixture/scripts" "$mp_fixture/.claude-plugin" "$mp_fixture/.agents/plugins" \
  "$mp_fixture/bin"
cp "$ROOT_DIR/scripts/manage-plugins.sh" "$mp_fixture/scripts/manage-plugins.sh"
cat >"$mp_fixture/.claude-plugin/marketplace.json" <<'JSON'
{"plugins":[{"name":"only-plugin","source":"./plugins/only-plugin"}]}
JSON
cat >"$mp_fixture/.agents/plugins/marketplace.json" <<'JSON'
{"plugins":[]}
JSON
cat >"$mp_fixture/bin/codex" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "plugin marketplace list --json") echo '{"marketplaces":[]}' ;;
  "plugin list --json") echo '{"installed":[]}' ;;
esac
STUB
chmod +x "$mp_fixture/bin/codex"
set +e
mp_out=$(PATH="$mp_fixture/bin:/usr/bin:/bin" \
  /bin/bash "$mp_fixture/scripts/manage-plugins.sh" uninstall --runtime codex --yes 2>&1)
mp_status=$?
set -e
[ "$mp_status" -eq 0 ] \
  || fail "/bin/bash manage-plugins.sh should not crash with zero compatible plugins: $mp_out"
case "$mp_out" in
  *"Nothing to uninstall"*) ;;
  *) fail "unexpected output with zero compatible plugins: $mp_out" ;;
esac

fake_home="$tmp_dir/home"
stub_bin="$tmp_dir/bin"
copilot_log="$tmp_dir/copilot.log"
mkdir -p "$fake_home/.codex/agents" "$fake_home/.codexbar" "$stub_bin"
printf 'user-owned\n' >"$fake_home/.codex/agents/repo-explorer.toml"
echo '{"hooks":{"enabled":false,"events":[]}}' >"$fake_home/.codexbar/config.json"

cat >"$stub_bin/copilot" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COPILOT_LOG"
case "$*" in
  "plugin marketplace list")
    echo "  • akunzai-agent-skills (GitHub: akunzai/agent-skills)"
    ;;
  "plugin list")
    if [[ -n "${COPILOT_PLUGIN_LIST:-}" ]]; then
      printf '%s\n' "$COPILOT_PLUGIN_LIST"
    else
      echo "  • charley-skills@akunzai-agent-skills (v1.0.0) (enabled)"
    fi
    ;;
esac
STUB
chmod +x "$stub_bin/copilot"

cat >"$stub_bin/codexbar" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "guard" ]]; then
  echo '{"decision":"ok","unavailableReason":null}'
  exit 0
fi
exit 1
STUB
chmod +x "$stub_bin/codexbar"

# Select every plugin interactively for Copilot. The installer must detect the
# existing charley-skills plugin, skip it, and install the other marketplace
# entries without inspecting or modifying Codex personal agents.
printf '1\nall\ny\n' | PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" \
  COPILOT_LOG="$copilot_log" bash "$SCRIPT" --interactive \
    --threshold 0.83 >/dev/null \
  || fail "interactive Copilot setup failed"

grep -qx 'plugin install codexbar-quota-handoff@akunzai-agent-skills' "$copilot_log" \
  || fail "interactive setup did not install codexbar-quota-handoff for Copilot"
grep -qx 'plugin install cheap-dev-workers@akunzai-agent-skills' "$copilot_log" \
  || fail "interactive setup did not install cheap-dev-workers for Copilot"
if grep -qx 'plugin install charley-skills@akunzai-agent-skills' "$copilot_log"; then
  fail "interactive setup reinstalled an existing Copilot plugin"
fi
grep -q 'user-owned' "$fake_home/.codex/agents/repo-explorer.toml" \
  || fail "Copilot setup modified a conflicting Codex personal agent"
jq -e '.hooks.events[] | select(.provider == "copilot") | .threshold == 0.83' \
  "$fake_home/.codexbar/config.json" >/dev/null \
  || fail "root setup did not forward --threshold to the CodexBar host helper"

# Upgrade and uninstall share the same installed-state detection. Both target
# Copilot only and must leave the conflicting Codex personal agent untouched.
copilot_installed='  • cheap-dev-workers@akunzai-agent-skills (v1.2.1) (enabled)'
printf '1\n2\ny\n' | PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" \
  COPILOT_LOG="$copilot_log" COPILOT_PLUGIN_LIST="$copilot_installed" \
  bash "$ROOT_DIR/scripts/upgrade.sh" --interactive >/dev/null \
  || fail "Copilot plugin upgrade failed"
grep -qx 'plugin marketplace update akunzai-agent-skills' "$copilot_log" \
  || fail "upgrade did not refresh the Copilot marketplace"
grep -qx 'plugin update cheap-dev-workers@akunzai-agent-skills' "$copilot_log" \
  || fail "upgrade did not update cheap-dev-workers for Copilot"

printf '1\n2\ny\n' | PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" \
  COPILOT_LOG="$copilot_log" COPILOT_PLUGIN_LIST="$copilot_installed" \
  bash "$ROOT_DIR/scripts/uninstall.sh" --interactive >/dev/null \
  || fail "Copilot plugin uninstall failed"
grep -qx 'plugin uninstall cheap-dev-workers@akunzai-agent-skills' "$copilot_log" \
  || fail "uninstall did not remove cheap-dev-workers from Copilot"
grep -q 'user-owned' "$fake_home/.codex/agents/repo-explorer.toml" \
  || fail "Copilot uninstall modified a conflicting Codex personal agent"

codexbar_state="$fake_home/.local/state/codexbar-quota-handoff"
mkdir -p "$codexbar_state"
touch "$codexbar_state/quota-low-copilot.json"
copilot_codexbar='  • codexbar-quota-handoff@akunzai-agent-skills (v1.1.0) (enabled)'
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" COPILOT_LOG="$copilot_log" \
  COPILOT_PLUGIN_LIST="$copilot_codexbar" \
  bash "$ROOT_DIR/scripts/uninstall.sh" --runtime copilot \
    --plugin codexbar-quota-handoff --keep-state --yes >/dev/null \
  || fail "CodexBar uninstall with --keep-state failed"
[ -f "$codexbar_state/quota-low-copilot.json" ] \
  || fail "root uninstall did not forward --keep-state to the CodexBar host helper"

# Without --keep-state, cleanup_args stays an empty array. Expanding
# "${cleanup_args[@]}" as a command's trailing arguments crashed macOS's
# stock /bin/bash 3.2 under `set -u` ("cleanup_args[@]: unbound variable"),
# so the CodexBar uninstall never reached remove-host.sh. Pin the
# interpreter explicitly so this does not silently pass by picking up a
# newer `bash` from PATH.
touch "$codexbar_state/quota-low-copilot.json"
set +e
sysbash_out=$(PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" COPILOT_LOG="$copilot_log" \
  COPILOT_PLUGIN_LIST="$copilot_codexbar" \
  /bin/bash "$ROOT_DIR/scripts/uninstall.sh" --runtime copilot \
    --plugin codexbar-quota-handoff --yes 2>&1)
sysbash_status=$?
set -e
[ "$sysbash_status" -eq 0 ] \
  || fail "/bin/bash CodexBar uninstall without --keep-state failed ($sysbash_status): $sysbash_out"
[ ! -f "$codexbar_state/quota-low-copilot.json" ] \
  || fail "uninstall without --keep-state left CodexBar state behind"

# Claude Code uses JSON status output. Existing plugins are skipped and the
# root charley-skills marketplace entry remains installable.
claude_log="$tmp_dir/claude.log"
cat >"$stub_bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLAUDE_LOG"
case "$*" in
  "plugin marketplace list --json")
    echo '[{"name":"akunzai-agent-skills"}]'
    ;;
  "plugin list --json")
    echo '[{"id":"cheap-dev-workers@akunzai-agent-skills","scope":"user"}]'
    ;;
esac
STUB
chmod +x "$stub_bin/claude"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$SCRIPT" --runtime claude --plugin all --yes >/dev/null \
  || fail "non-interactive Claude Code setup failed"
grep -qx 'plugin install charley-skills@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "setup did not install charley-skills for Claude Code"
grep -qx 'plugin install codexbar-quota-handoff@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "setup did not install codexbar-quota-handoff for Claude Code"
if grep -qx 'plugin install cheap-dev-workers@akunzai-agent-skills --scope user --yes' "$claude_log"; then
  fail "setup reinstalled an existing Claude Code plugin"
fi

# Installed detection is scope-specific: a user install must not suppress a
# requested project-scope install of the same plugin.
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$SCRIPT" --runtime claude --plugin cheap-dev-workers \
    --scope project --yes >/dev/null \
  || fail "project-scope Claude Code setup failed"
grep -qx 'plugin install cheap-dev-workers@akunzai-agent-skills --scope project --yes' "$claude_log" \
  || fail "setup treated a user-scope Claude plugin as installed at project scope"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$ROOT_DIR/scripts/upgrade.sh" --runtime claude \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Claude Code plugin upgrade failed"
grep -qx 'plugin marketplace update akunzai-agent-skills' "$claude_log" \
  || fail "upgrade did not refresh the Claude Code marketplace"
grep -qx 'plugin update cheap-dev-workers@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "upgrade did not update cheap-dev-workers for Claude Code"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$ROOT_DIR/scripts/uninstall.sh" --runtime claude \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Claude Code plugin uninstall failed"
grep -qx 'plugin uninstall cheap-dev-workers@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "uninstall did not remove cheap-dev-workers from Claude Code"

# Codex also exposes JSON status. Every entry is listed in the Codex
# marketplace, so charley-skills installs alongside the sub-plugins.
codex_log="$tmp_dir/codex.log"
cat >"$stub_bin/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CODEX_LOG"
case "$*" in
  "plugin marketplace list --json")
    echo '{"marketplaces":[{"name":"akunzai-agent-skills"}]}'
    ;;
  "plugin list --json")
    echo '{"installed":[{"pluginId":"cheap-dev-workers@akunzai-agent-skills","installed":true}]}'
    ;;
esac
STUB
chmod +x "$stub_bin/codex"

rm "$fake_home/.codex/agents/repo-explorer.toml"
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$SCRIPT" --runtime codex --plugin all --yes >/dev/null \
  || fail "non-interactive Codex setup failed"
grep -qx 'plugin add codexbar-quota-handoff@akunzai-agent-skills' "$codex_log" \
  || fail "setup did not install codexbar-quota-handoff for Codex"
grep -qx 'plugin add charley-skills@akunzai-agent-skills' "$codex_log" \
  || fail "setup did not install charley-skills for Codex"
if grep -qx 'plugin add cheap-dev-workers@akunzai-agent-skills' "$codex_log"; then
  fail "setup reinstalled an existing Codex plugin"
fi
[ ! -e "$fake_home/.codex/agents/repo-explorer.toml" ] \
  || fail "setup ran Codex agent post-install for an already-installed plugin"

mkdir -p "$fake_home/.codex/agents"
printf 'retired\n' >"$fake_home/.codex/agents/commit-writer.toml"
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$ROOT_DIR/scripts/upgrade.sh" --runtime codex \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Codex plugin upgrade failed"
grep -qx 'plugin marketplace upgrade akunzai-agent-skills' "$codex_log" \
  || fail "upgrade did not refresh the Codex marketplace snapshot"
for name in repo-explorer.toml check-runner.toml log-summarizer.toml; do
  diff -q "$ROOT_DIR/plugins/cheap-dev-workers/codex-agents/$name" \
    "$fake_home/.codex/agents/$name" >/dev/null \
    || fail "Codex upgrade did not sync $name"
done
[ ! -e "$fake_home/.codex/agents/commit-writer.toml" ] \
  || fail "Codex upgrade left leftover commit-writer.toml"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$ROOT_DIR/scripts/uninstall.sh" --runtime codex \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Codex plugin uninstall failed"
grep -qx 'plugin remove cheap-dev-workers@akunzai-agent-skills' "$codex_log" \
  || fail "uninstall did not remove cheap-dev-workers from Codex"
for name in repo-explorer.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ ! -e "$fake_home/.codex/agents/$name" ] \
    || fail "Codex uninstall left $name behind"
done

echo "plugin setup checks passed"
