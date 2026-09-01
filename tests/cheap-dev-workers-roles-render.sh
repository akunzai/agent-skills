#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/cheap-dev-workers"
RENDER="$PLUGIN_DIR/scripts/render-roles.sh"

fail() {
  echo "cheap-dev-workers roles render check failed: $*" >&2
  exit 1
}

[ -x "$RENDER" ] || fail "$RENDER is missing or not executable"

# --- the committed artifacts are exactly what roles/ projects ---
"$RENDER" --check >/dev/null || fail "committed artifacts have drifted from roles/"

# --- the safety-critical invariants each role must carry ---
# Locks are on stable ids, not on prose: normalizing the wording later must not
# break these, which is exactly how the old phrase greps failed.
declares() {
  awk -v want_id="$1" -v want_role="$2" '
    /^id / { id = $2 }
    /^applies / {
      if (id != want_id) next
      for (i = 2; i <= NF; i++) if ($i == want_role) { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  ' "$PLUGIN_DIR/roles/shared.role"
}

require_ids() {
  local role="$1"
  shift
  local id
  for id in "$@"; do
    declares "$id" "$role" \
      || fail "shared.role does not apply '$id' to $role"
  done
}

for role in check-runner commit-writer log-summarizer repo-explorer; do
  require_ids "$role" git.no-mutation role.description
done
require_ids check-runner checks.caller-named artifacts.tracked-source \
  git.fingerprint evidence.per-check evidence.check-cardinality \
  evidence.no-invention relay.target relay.nesting-limit relay.child-boundary
require_ids repo-explorer scope.caller-repo evidence.cited \
  verification.reserved relay.trigger relay.target relay.nesting-limit \
  relay.child-boundary decisions.none
require_ids log-summarizer role.leaf scope.exact-artifact input.rejection \
  summary.root-causes secrets.residual-scan
require_ids commit-writer role.leaf boundaries.caller-decided \
  input.caller-supplied message.why-not-what pr.shape issue.linking \
  output.contract

# --- usage errors are refused, not guessed at ---
"$RENDER" >/dev/null 2>&1 && fail "a missing mode must be an error"
"$RENDER" --runtime codex >/dev/null 2>&1 && fail "an unknown option must be an error"
"$RENDER" --check --write >/dev/null 2>&1 && fail "two modes must be an error"

# --- behaviour on a disposable copy: nothing below touches the real plugin ---
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SANDBOX="$TMP_DIR/cheap-dev-workers"
mkdir -p "$SANDBOX"
cp -R "$PLUGIN_DIR/roles" "$PLUGIN_DIR/scripts" "$PLUGIN_DIR/agents" \
  "$PLUGIN_DIR/codex-agents" "$SANDBOX/"
COPY="$SANDBOX/scripts/render-roles.sh"

"$COPY" --check >/dev/null || fail "the copied tree should render identically"

expect_exit() {
  local want="$1" label="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "$label expected exit $want, got $got"
}

# A hand-edited artifact is drift, not a new source of truth.
printf '\nhand-edited\n' >> "$SANDBOX/agents/check-runner.md"
expect_exit 1 "hand-edited artifact" "$COPY" --check
cp "$PLUGIN_DIR/agents/check-runner.md" "$SANDBOX/agents/check-runner.md"

# An unknown directive is rejected rather than ignored.
printf 'wobble claude\n' >> "$SANDBOX/roles/check-runner.role"
expect_exit 65 "unknown directive" "$COPY" --check
cp "$PLUGIN_DIR/roles/check-runner.role" "$SANDBOX/roles/check-runner.role"

# An id that is not declared in the shared skeleton is rejected.
sed 's/^entry output.contract$/entry output.contract nope.id/' \
  "$PLUGIN_DIR/roles/commit-writer.role" > "$SANDBOX/roles/commit-writer.role"
expect_exit 65 "undeclared id" "$COPY" --check
cp "$PLUGIN_DIR/roles/commit-writer.role" "$SANDBOX/roles/commit-writer.role"

# The role set is fixed: an extra source is a hard error.
cp "$SANDBOX/roles/check-runner.role" "$SANDBOX/roles/extra.role"
expect_exit 65 "extra role source" "$COPY" --check
rm "$SANDBOX/roles/extra.role"

# --write leaves every artifact untouched when any role fails validation.
printf 'wobble claude\n' >> "$SANDBOX/roles/repo-explorer.role"
printf '\nhand-edited\n' >> "$SANDBOX/agents/check-runner.md"
before="$(cksum < "$SANDBOX/agents/check-runner.md")"
expect_exit 65 "--write with an invalid source" "$COPY" --write
after="$(cksum < "$SANDBOX/agents/check-runner.md")"
[ "$before" = "$after" ] || fail "--write applied a partial render despite a validation failure"

echo "cheap-dev-workers roles render checks passed"
