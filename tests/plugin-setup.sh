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

export AGENT_SKILLS_OS="darwin"

for script in setup.sh upgrade.sh uninstall.sh manage-plugins.sh; do
  [ -x "$ROOT_DIR/scripts/$script" ] \
    || fail "scripts/$script is missing or not executable"
done

# The repository-level lifecycle scripts are the only public entry points.
# Plugin directories may contain internal helpers, but no compatibility
# setup/upgrade/uninstall wrappers.
for plugin in cheap-dev-workers codexbar-quota-handoff spoken-tts; do
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
real_jq="$(command -v jq)" || fail "jq is required to run this test"
cat >"$mp_fixture/bin/jq" <<STUB
#!/usr/bin/env bash
exec "$real_jq" "\$@"
STUB
chmod +x "$mp_fixture/bin/jq"
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
export HOME="$fake_home"
export XDG_CONFIG_HOME="$fake_home/.config"
export XDG_STATE_HOME="$fake_home/.local/state"
export XDG_DATA_HOME="$fake_home/.local/share"
stub_bin="$tmp_dir/bin"
copilot_log="$tmp_dir/copilot.log"
mkdir -p "$fake_home/.codex/agents" "$fake_home/.codexbar" "$stub_bin" \
  "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
cat >"$stub_bin/jq" <<STUB
#!/usr/bin/env bash
exec "$real_jq" "\$@"
STUB
chmod +x "$stub_bin/jq"
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
      echo "  • spoken-tts@akunzai-agent-skills (v1.0.0) (enabled)"
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
# existing spoken-tts plugin, skip it, and install the other marketplace
# entries without inspecting or modifying Codex personal agents.
printf '1\nall\ny\n' | PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" \
  COPILOT_LOG="$copilot_log" bash "$SCRIPT" --interactive \
    --threshold 0.83 >/dev/null \
  || fail "interactive Copilot setup failed"

grep -qx 'plugin install codexbar-quota-handoff@akunzai-agent-skills' "$copilot_log" \
  || fail "interactive setup did not install codexbar-quota-handoff for Copilot"
grep -qx 'plugin install cheap-dev-workers@akunzai-agent-skills' "$copilot_log" \
  || fail "interactive setup did not install cheap-dev-workers for Copilot"
if grep -qx 'plugin install spoken-tts@akunzai-agent-skills' "$copilot_log"; then
  fail "interactive setup reinstalled an existing Copilot plugin"
fi
if grep -qx 'plugin install charley-skills@akunzai-agent-skills' "$copilot_log"; then
  fail "setup installed catalog skills as a plugin"
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

# Claude Code uses JSON status output. Existing plugins are skipped and
# catalog skills are not installed as a plugin.
claude_log="$tmp_dir/claude.log"
cat >"$stub_bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLAUDE_LOG"
case "$*" in
  "plugin marketplace list --json")
    if [[ -n "${CLAUDE_MARKETPLACES:-}" ]]; then
      printf '%s\n' "$CLAUDE_MARKETPLACES"
    else
      echo '[{"name":"akunzai-agent-skills"}]'
    fi
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
grep -qx 'plugin install spoken-tts@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "setup did not install spoken-tts for Claude Code"
grep -qx 'plugin install codexbar-quota-handoff@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "setup did not install codexbar-quota-handoff for Claude Code"
if grep -qx 'plugin install charley-skills@akunzai-agent-skills --scope user --yes' "$claude_log"; then
  fail "setup installed catalog skills as a plugin"
fi
if grep -qx 'plugin install cheap-dev-workers@akunzai-agent-skills --scope user --yes' "$claude_log"; then
  fail "setup reinstalled an existing Claude Code plugin"
fi

# Windows jq.exe ends every line with CRLF; plugin names must stay clean.
crlf_bin="$tmp_dir/crlf-bin"
mkdir -p "$crlf_bin"
real_jq="$(command -v jq)"
cat >"$crlf_bin/jq" <<STUB
#!/usr/bin/env bash
"$real_jq" "\$@" | sed 's/\$/\r/'
exit "\${PIPESTATUS[0]}"
STUB
chmod +x "$crlf_bin/jq"
: >"$claude_log"
PATH="$crlf_bin:$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$SCRIPT" --runtime claude --plugin all --yes >/dev/null \
  || fail "setup failed with a CRLF-emitting jq"
grep -qx 'plugin install spoken-tts@akunzai-agent-skills --scope user --yes' "$claude_log" \
  || fail "CRLF jq leaked carriage returns into plugin names"

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

# A marketplace declared in settings.json under one source and registered
# under another breaks every /plugin run, so setup refuses to create or
# extend that split.
mkdir -p "$fake_home/.claude"
echo '{"extraKnownMarketplaces":{"akunzai-agent-skills":{"source":{"source":"github","repo":"akunzai/agent-skills"}}}}' \
  >"$fake_home/.claude/settings.json"

: >"$claude_log"
set +e
split_out=$(PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  CLAUDE_MARKETPLACES='[]' \
  bash "$SCRIPT" --runtime claude --plugin spoken-tts --local --yes 2>&1)
split_status=$?
set -e
[ "$split_status" -ne 0 ] || fail "setup --local registered a source settings.json does not declare"
case "$split_out" in *"drop --local"*) ;; *) fail "declared-source refusal lacks its fix: $split_out" ;; esac
! grep -q '^plugin marketplace add' "$claude_log" \
  || fail "setup added a marketplace that contradicts settings.json"

set +e
split_out=$(PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  CLAUDE_MARKETPLACES="[{\"name\":\"akunzai-agent-skills\",\"source\":\"directory\",\"path\":\"$ROOT_DIR\"}]" \
  bash "$ROOT_DIR/scripts/upgrade.sh" --runtime claude --plugin cheap-dev-workers --yes 2>&1)
split_status=$?
set -e
[ "$split_status" -ne 0 ] || fail "upgrade ignored a registered/declared marketplace split"
case "$split_out" in *"claude plugin marketplace remove akunzai-agent-skills"*) ;;
  *) fail "split refusal lacks the remove command: $split_out" ;; esac
! grep -q '^plugin update' "$claude_log" || fail "upgrade proceeded despite the split"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  CLAUDE_MARKETPLACES='[{"name":"akunzai-agent-skills","source":"github","repo":"akunzai/agent-skills"}]' \
  bash "$ROOT_DIR/scripts/upgrade.sh" --runtime claude --plugin cheap-dev-workers --yes >/dev/null \
  || fail "upgrade refused a marketplace that matches settings.json"
rm "$fake_home/.claude/settings.json"

# Codex also exposes JSON status. Catalog skills are not a marketplace
# plugin; remaining entries install alongside each other.
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
cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/log-summarizer-released.toml" \
  "$fake_home/.codex/agents/log-summarizer.toml"
for role in commit-writer check-runner; do
  cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/$role-released.toml" \
    "$fake_home/.codex/agents/$role.toml"
done
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$SCRIPT" --runtime codex --plugin all --yes >/dev/null \
  || fail "non-interactive Codex setup failed"
grep -qx 'plugin add codexbar-quota-handoff@akunzai-agent-skills' "$codex_log" \
  || fail "setup did not install codexbar-quota-handoff for Codex"
grep -qx 'plugin add spoken-tts@akunzai-agent-skills' "$codex_log" \
  || fail "setup did not install spoken-tts for Codex"
if grep -qx 'plugin add charley-skills@akunzai-agent-skills' "$codex_log"; then
  fail "setup installed catalog skills as a plugin"
fi
if grep -qx 'plugin add cheap-dev-workers@akunzai-agent-skills' "$codex_log"; then
  fail "setup reinstalled an existing Codex plugin"
fi
for name in repo-explorer.toml evidence-collector.toml log-summarizer.toml; do
  cmp -s "$ROOT_DIR/plugins/cheap-dev-workers/codex-agents/$name" \
    "$fake_home/.codex/agents/$name" \
    || fail "setup did not reconcile $name for an already-installed Codex plugin"
done
for role in commit-writer check-runner; do
  [ ! -e "$fake_home/.codex/agents/$role.toml" ] \
    || fail "setup did not retire a released $role for an already-installed plugin"
done

# Reconcile even when no plugin needs installing (the single-plugin no-op path).
rm "$fake_home/.codex/agents/repo-explorer.toml"
cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/commit-writer-released.toml" \
  "$fake_home/.codex/agents/commit-writer.toml"
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$SCRIPT" --runtime codex --plugin cheap-dev-workers --yes >/dev/null \
  || fail "setup failed to reconcile the only selected installed plugin"
[ -f "$fake_home/.codex/agents/repo-explorer.toml" ] \
  || fail "setup skipped missing agents when no plugin needed installation"
[ ! -e "$fake_home/.codex/agents/commit-writer.toml" ] \
  || fail "setup skipped retirement when no plugin needed installation"
! grep -qx 'plugin add cheap-dev-workers@akunzai-agent-skills' "$codex_log" \
  || fail "single-plugin setup reinstalled an existing Codex plugin"

mkdir -p "$fake_home/.codex/agents"
cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/commit-writer-released.toml" \
  "$fake_home/.codex/agents/commit-writer.toml"
cp "$ROOT_DIR/tests/fixtures/cheap-dev-workers/check-runner-released.toml" \
  "$fake_home/.codex/agents/check-runner.toml"
PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$ROOT_DIR/scripts/upgrade.sh" --runtime codex \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Codex plugin upgrade failed"
grep -qx 'plugin marketplace upgrade akunzai-agent-skills' "$codex_log" \
  || fail "upgrade did not refresh the Codex marketplace snapshot"
for name in repo-explorer.toml evidence-collector.toml log-summarizer.toml; do
  diff -q "$ROOT_DIR/plugins/cheap-dev-workers/codex-agents/$name" \
    "$fake_home/.codex/agents/$name" >/dev/null \
    || fail "Codex upgrade did not sync $name"
done
[ ! -e "$fake_home/.codex/agents/commit-writer.toml" ] \
  || fail "Codex upgrade left leftover commit-writer.toml"
[ ! -e "$fake_home/.codex/agents/check-runner.toml" ] \
  || fail "Codex upgrade left a released check-runner.toml"

PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CODEX_LOG="$codex_log" \
  bash "$ROOT_DIR/scripts/uninstall.sh" --runtime codex \
    --plugin cheap-dev-workers --yes >/dev/null \
  || fail "Codex plugin uninstall failed"
grep -qx 'plugin remove cheap-dev-workers@akunzai-agent-skills' "$codex_log" \
  || fail "uninstall did not remove cheap-dev-workers from Codex"
for name in repo-explorer.toml evidence-collector.toml check-runner.toml log-summarizer.toml commit-writer.toml; do
  [ ! -e "$fake_home/.codex/agents/$name" ] \
    || fail "Codex uninstall left $name behind"
done

# --- Windows checks: codexbar-quota-handoff is excluded on Windows ---
set +e
win_out=$(AGENT_SKILLS_OS="windows" PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" \
  bash "$SCRIPT" --runtime claude --plugin codexbar-quota-handoff --yes 2>&1)
win_status=$?
set -e
[ "$win_status" -ne 0 ] || fail "Windows setup should reject codexbar-quota-handoff"
case "$win_out" in
  *"codexbar-quota-handoff requires macOS"*) ;;
  *) fail "Windows setup rejection lacked macOS message: $win_out" ;;
esac

: >"$claude_log"
AGENT_SKILLS_OS="windows" PATH="$stub_bin:/usr/bin:/bin" HOME="$fake_home" CLAUDE_LOG="$claude_log" \
  bash "$SCRIPT" --runtime claude --plugin all --yes >/dev/null \
  || fail "Windows setup with --plugin all failed"
! grep -q 'codexbar-quota-handoff' "$claude_log" \
  || fail "Windows setup --plugin all should not install codexbar-quota-handoff"

echo "plugin setup checks passed"
