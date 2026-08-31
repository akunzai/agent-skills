#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"

fail() {
  echo "cheap-dev-workers agents content check failed: $*" >&2
  exit 1
}

# --- both runtimes leave model and effort selection to the caller ---
for role in repo-explorer check-runner log-summarizer commit-writer; do
  ! grep -q '^model:' "$PLUGIN_DIR/agents/$role.md" \
    || fail "$role Claude model must remain runtime-selected"
  ! grep -q '^effort:' "$PLUGIN_DIR/agents/$role.md" \
    || fail "$role Claude effort must remain inherited"
  tr '\n' ' ' < "$PLUGIN_DIR/agents/$role.md" | grep -qi 'cheapest.*capable' \
    || fail "$role Claude description lacks dynamic cost routing"
  tr -s '[:space:]' ' ' < "$PLUGIN_DIR/agents/$role.md" \
    | grep -qi 'prefer this over a general-purpose agent' \
    || fail "$role Claude description lacks the generic-agent routing preference"
  tr -s '[:space:]' ' ' < "$PLUGIN_DIR/codex-agents/$role.toml" \
    | grep -qi 'prefer over a generic worker' \
    || fail "$role Codex description lacks the generic-agent routing preference"
  ! grep -q '^model = ' "$PLUGIN_DIR/codex-agents/$role.toml" \
    || fail "$role Codex model must remain runtime-selected"
  ! grep -q '^model_reasoning_effort = ' "$PLUGIN_DIR/codex-agents/$role.toml" \
    || fail "$role Codex reasoning effort must remain runtime-selected"
done

# --- all definitions carry the same Git-state boundary ---
for f in "$PLUGIN_DIR"/agents/*.md "$PLUGIN_DIR"/codex-agents/*.toml; do
  grep -qi 'read-only\|tracked source' "$f" || fail "$f lacks permission boundary"
  grep -qi 'never' "$f" || fail "$f lacks mutation prohibition"
  grep -qi 'stage\|git add' "$f" || fail "$f lacks staging boundary"
  grep -qi 'index\|refs\|remotes' "$f" || fail "$f lacks Git-state boundary"
done

# --- both commit-writer variants must be explicitly read-only ---
for f in "$PLUGIN_DIR/agents/commit-writer.md" "$PLUGIN_DIR/codex-agents/commit-writer.toml"; do
  grep -q -F 'Read-only' "$f" || grep -q -F 'read-only' "$f" \
    || fail "$f must state it is read-only"
  grep -q -F 'git commit' "$f" || fail "$f must name git commit among the commands it never runs"
done

for role in repo-explorer log-summarizer commit-writer; do
  grep -q '^sandbox_mode = "read-only"$' "$PLUGIN_DIR/codex-agents/$role.toml" || fail "$role must be read-only"
done
grep -q '^sandbox_mode = "workspace-write"$' \
  "$PLUGIN_DIR/codex-agents/check-runner.toml" \
  || fail "check-runner needs build artifacts"
grep -q '^tools: Read, Grep, Glob$' "$PLUGIN_DIR/agents/repo-explorer.md" || fail "Claude explorer has excess tools"
grep -q '^tools: Bash, Read$' "$PLUGIN_DIR/agents/check-runner.md" || fail "Claude check-runner has excess tools"
grep -q '^tools: Read$' "$PLUGIN_DIR/agents/commit-writer.md" || fail "Claude commit writer has excess tools"

for f in "$PLUGIN_DIR/agents/check-runner.md" "$PLUGIN_DIR/codex-agents/check-runner.toml"; do
  grep -Fq 'git diff --no-ext-diff --binary HEAD -- | git hash-object --stdin' "$f" \
    || fail "$f lacks tracked-state fingerprinting"
  grep -qi 'every check' "$f" || fail "$f lacks per-check evidence cardinality"
  grep -qi 'caller-named command' "$f" || fail "$f leaves check cardinality ambiguous"
  grep -qi 'never invent counts or outcomes' "$f" \
    || fail "$f allows unobserved evidence claims"
  for evidence in 'exact command' 'exit code' 'root-cause' 'summary block' 'omitted lines' 'artifact'; do
    grep -qi "$evidence" "$f" || fail "$f lacks $evidence"
  done
  grep -qi 'log-summarizer' "$f" || fail "$f lacks relay target"
done
for f in "$PLUGIN_DIR/agents/repo-explorer.md" "$PLUGIN_DIR/codex-agents/repo-explorer.toml"; do
  grep -qi 'file.*line' "$f" || fail "$f lacks cited evidence"
  grep -qi 'check-runner' "$f" || fail "$f lacks relay target"
  grep -qi 'do not run test, build, lint' "$f" \
    || fail "$f does not reserve checks for check-runner"
  grep -qi 'explicitly requests verification' "$f" \
    || fail "$f lacks a deterministic relay trigger"
done
for f in "$PLUGIN_DIR/agents/commit-writer.md" \
  "$PLUGIN_DIR/codex-agents/commit-writer.toml"; do
  grep -qi 'supplied recent.*subjects' "$f" \
    || fail "$f expands beyond caller-supplied style evidence"
done
for f in "$PLUGIN_DIR/codex-agents/repo-explorer.toml" \
  "$PLUGIN_DIR/codex-agents/check-runner.toml"; do
  grep -qi 'minimum context' "$f" || fail "$f lacks minimum-context rule"
  grep -qi 'permission boundary' "$f" || fail "$f lacks child permission rule"
  grep -qi 'four-worker' "$f" || fail "$f lacks concurrency budget"
  grep -qi 'never retry.*launch failure' "$f" || fail "$f lacks no-retry rule"
done
for f in "$PLUGIN_DIR/agents/repo-explorer.md" "$PLUGIN_DIR/agents/check-runner.md"; do
  ! grep -q '^tools:.*Agent' "$f" || fail "$f claims unsupported Claude nesting"
  grep -qi 'primary relay' "$f" || fail "$f lacks Claude primary relay"
  grep -qi 'permission boundary' "$f" || fail "$f lacks relay permission rule"
  grep -qi 'four-worker' "$f" || fail "$f lacks concurrency budget"
done

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
for role in log-summarizer commit-writer; do
  grep -qi 'leaf' "$PLUGIN_DIR/agents/$role.md" || fail "$role must be a leaf"
  grep -qi 'leaf' "$PLUGIN_DIR/codex-agents/$role.toml" || fail "$role must be a leaf"
done

grep -qi 'repository scope' "$PLUGIN_DIR/codex-agents/repo-explorer.toml" \
  || fail "Codex explorer scope drift"
grep -qi 'unresolved uncertainty' "$PLUGIN_DIR/codex-agents/repo-explorer.toml" \
  || fail "Codex explorer evidence drift"
grep -qi 'root causes and important events' "$PLUGIN_DIR/codex-agents/log-summarizer.toml" \
  || fail "Codex summarizer purpose drift"
grep -qi 'caller-supplied diff' "$PLUGIN_DIR/agents/commit-writer.md" \
  || fail "Claude commit-writer input drift"
grep -qi 'caller-supplied diff' "$PLUGIN_DIR/codex-agents/commit-writer.toml" \
  || fail "Codex commit-writer input drift"

# --- required TOML fields present on both codex agents ---
for f in "$PLUGIN_DIR"/codex-agents/*.toml; do
  grep -q '^name = ' "$f" || fail "$f is missing a name field"
  grep -q '^description = ' "$f" || fail "$f is missing a description field"
  grep -q '^developer_instructions = """$' "$f" || fail "$f is missing a developer_instructions block"
done

echo "cheap-dev-workers agents content checks passed"
