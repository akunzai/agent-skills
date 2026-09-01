#!/usr/bin/env bash
set -euo pipefail

# Native seam checks only. Cross-runtime parity used to be asserted here with
# phrase greps; it is now structural, because both artifact sets are projected
# from plugins/cheap-dev-workers/roles/ and every entry must produce prose for
# both runtimes. See tests/cheap-dev-workers-roles-render.sh for the canonical
# layer, and the plugin's AGENTS.md for what these checks do not prove.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"

fail() {
  echo "cheap-dev-workers agents content check failed: $*" >&2
  exit 1
}

ROLES=(repo-explorer check-runner log-summarizer commit-writer)

for role in "${ROLES[@]}"; do
  md="$PLUGIN_DIR/agents/$role.md"
  toml="$PLUGIN_DIR/codex-agents/$role.toml"
  [ -f "$md" ] || fail "$role is missing its Claude definition"
  [ -f "$toml" ] || fail "$role is missing its Codex definition"

  # --- both runtimes leave model and effort selection to the caller ---
  ! grep -q '^model:' "$md" || fail "$role Claude model must remain runtime-selected"
  ! grep -q '^effort:' "$md" || fail "$role Claude effort must remain inherited"
  ! grep -q '^model = ' "$toml" || fail "$role Codex model must remain runtime-selected"
  ! grep -q '^model_reasoning_effort = ' "$toml" \
    || fail "$role Codex reasoning effort must remain runtime-selected"

  # --- the description is the only routing surface the runtimes expose ---
  tr -s '[:space:]' ' ' < "$md" | grep -qi 'cheapest.*capable' \
    || fail "$role Claude description lacks dynamic cost routing"
  tr -s '[:space:]' ' ' < "$md" | grep -qi 'prefer this over a general-purpose agent' \
    || fail "$role Claude description lacks the generic-agent routing preference"
  tr -s '[:space:]' ' ' < "$toml" | grep -qi 'prefer over a generic worker' \
    || fail "$role Codex description lacks the generic-agent routing preference"

  # --- Claude plugin subagents cannot nest, so no role may claim otherwise ---
  ! grep -q '^tools:.*Agent' "$md" || fail "$role claims unsupported Claude nesting"

  # --- required Codex fields ---
  grep -q '^name = ' "$toml" || fail "$toml is missing a name field"
  grep -q '^description = ' "$toml" || fail "$toml is missing a description field"
  grep -q '^developer_instructions = """$' "$toml" \
    || fail "$toml is missing a developer_instructions block"
done

# --- one capability, two native permission fields; they must not diverge ---
expect_permissions() {
  local role="$1" tools="$2" sandbox="$3"
  grep -q "^tools: $tools\$" "$PLUGIN_DIR/agents/$role.md" \
    || fail "$role Claude tools must be exactly '$tools'"
  grep -q "^sandbox_mode = \"$sandbox\"\$" "$PLUGIN_DIR/codex-agents/$role.toml" \
    || fail "$role Codex sandbox_mode must be exactly '$sandbox'"
}
expect_permissions repo-explorer 'Read, Grep, Glob' read-only
expect_permissions check-runner 'Bash, Read' workspace-write
expect_permissions log-summarizer 'Read' read-only
expect_permissions commit-writer 'Read' read-only

# --- the routing layer these roles plug into is documented, not inferred ---
grep -q 'cheap-dev-workers:<role>' "$PLUGIN_DIR/AGENTS.md" \
  || fail "Claude qualified dispatch adapter is undocumented"
grep -q 'Skills request roles' "$PLUGIN_DIR/AGENTS.md" \
  || fail "portable skill routing layer is undocumented"
grep -q 'do not support.*hooks.*permissionMode' "$PLUGIN_DIR/AGENTS.md" \
  || fail "Claude plugin permission limitation is undocumented"
grep -qi 'Choose the role before the model' "$PLUGIN_DIR/AGENTS.md" \
  || fail "role-before-model routing order is undocumented"
grep -qi "State the preference in each role's .description." "$PLUGIN_DIR/AGENTS.md" \
  || fail "description-carries-the-preference rule is undocumented"

echo "cheap-dev-workers agents content checks passed"
