#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/setup-agent-ready-repo/scripts/check-drift.sh"

fail() {
  echo "setup-agent-ready-repo-drift test failed: $*" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "Script $SCRIPT is missing or not executable"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- a repo whose documentation matches reality ---
REPO="$TMP_DIR/clean"
mkdir -p "$REPO/docs/agents" "$REPO/scripts" "$REPO/fixtures"
git -C "$REPO" init -b main >/dev/null
git -C "$REPO" remote add origin https://github.com/example/demo.git
printf 'services:\n  web:\n    ports:\n      - "8080:8080"\n' > "$REPO/compose.yml"
cat > "$REPO/scripts/dev-up.sh" <<'ENTRY'
#!/usr/bin/env bash
# Honours the documented detection order and rejects unknown
# arguments, so a caller passing a flag instead of the environment
# fails here rather than silently passing.
set -euo pipefail
[ $# -eq 0 ] || exit 64
[ "${NON_INTERACTIVE:-}" = "true" ] || [ "${CI:-}" = "true" ] || exit 65
ENTRY
chmod +x "$REPO/scripts/dev-up.sh"
touch "$REPO/fixtures/tenant.json"
cat > "$REPO/docs/agents/verification.md" <<'DOC'
# Verification

<!-- drift:forge github -->
<!-- drift:entrypoint scripts/dev-up.sh -->
<!-- drift:port 8080 -->
<!-- drift:file fixtures/tenant.json -->
DOC

OUT="$("$SCRIPT" "$REPO")" || fail "clean repo should exit 0: $OUT"
echo "$OUT" | grep -q "No drift found" || fail "clean repo missing summary: $OUT"
echo "$OUT" | grep -q "^ok    forge: github" || fail "forge not reported ok: $OUT"

# --run-entrypoint executes the recorded script
OUT="$("$SCRIPT" --run-entrypoint "$REPO")" || fail "clean repo with --run-entrypoint should exit 0: $OUT"
echo "$OUT" | grep -q "ran clean" || fail "entrypoint not executed: $OUT"

# flag may appear after DIR
"$SCRIPT" "$REPO" --run-entrypoint >/dev/null || fail "flag after DIR should work"

# --- each drift is detected independently ---
drift_case() {
  local name="$1" pattern="$2" mutate="$3"
  local repo="$TMP_DIR/$name"
  rm -rf "$repo"
  cp -R "$REPO" "$repo"
  "$mutate" "$repo"
  local out status=0
  out="$("$SCRIPT" "$repo" 2>/dev/null)" || status=$?
  [ "$status" -eq 1 ] || fail "$name should exit 1, got $status: $out"
  echo "$out" | grep -q "$pattern" || fail "$name missing '$pattern': $out"
}

move_forge() { git -C "$1" remote set-url origin https://gitlab.com/example/demo.git; }
remove_entrypoint() { rm "$1/scripts/dev-up.sh"; }
unexecutable_entrypoint() { chmod -x "$1/scripts/dev-up.sh"; }
renumber_port() { printf 'services:\n  web:\n    ports:\n      - "9090:9090"\n' > "$1/compose.yml"; }
remove_fixture() { rm "$1/fixtures/tenant.json"; }

drift_case forge-moved 'DRIFT forge:' move_forge
drift_case entrypoint-gone 'DRIFT entrypoint:.*no longer exists' remove_entrypoint
drift_case entrypoint-not-executable 'DRIFT entrypoint:.*not executable' unexecutable_entrypoint
drift_case port-gone 'DRIFT port 8080' renumber_port
drift_case file-gone 'DRIFT file: fixtures/tenant.json' remove_fixture

# a failing entrypoint only surfaces under --run-entrypoint
FAILING="$TMP_DIR/failing"
cp -R "$REPO" "$FAILING"
printf '#!/usr/bin/env bash\nexit 3\n' > "$FAILING/scripts/dev-up.sh"  # noqa: intentionally broken
chmod +x "$FAILING/scripts/dev-up.sh"
"$SCRIPT" "$FAILING" >/dev/null || fail "failing entrypoint should pass the presence check"
STATUS=0
OUT="$("$SCRIPT" --run-entrypoint "$FAILING" 2>/dev/null)" || STATUS=$?
[ "$STATUS" -eq 1 ] || fail "failing entrypoint should exit 1 under --run-entrypoint"
echo "$OUT" | grep -q "exited non-zero" || fail "failing entrypoint not reported: $OUT"

# --- conservative cases report skip rather than false drift ---
SELFHOSTED="$TMP_DIR/selfhosted"
cp -R "$REPO" "$SELFHOSTED"
git -C "$SELFHOSTED" remote set-url origin https://git.example.test/team/demo.git
OUT="$("$SCRIPT" "$SELFHOSTED")" || fail "unidentifiable host should not be drift: $OUT"
echo "$OUT" | grep -q "skip  forge:" || fail "self-hosted host should skip: $OUT"

NOCOMPOSE="$TMP_DIR/nocompose"
cp -R "$REPO" "$NOCOMPOSE"
rm "$NOCOMPOSE/compose.yml"
OUT="$("$SCRIPT" "$NOCOMPOSE")" || fail "missing compose should not be drift: $OUT"
echo "$OUT" | grep -q "skip  port 8080" || fail "missing compose should skip: $OUT"

# a documented forge with no remote at all is drift
NOREMOTE="$TMP_DIR/noremote"
cp -R "$REPO" "$NOREMOTE"
git -C "$NOREMOTE" remote remove origin
STATUS=0
OUT="$("$SCRIPT" "$NOREMOTE" 2>/dev/null)" || STATUS=$?
[ "$STATUS" -eq 1 ] || fail "documented forge with no remote should be drift"
echo "$OUT" | grep -q "no origin remote" || fail "no-remote drift not reported: $OUT"

# --- an unedited template reports drift rather than passing quietly ---
TEMPLATE="$ROOT_DIR/skills/setup-agent-ready-repo/references/templates/verification.md"
PLACEHOLDER="$TMP_DIR/placeholder"
mkdir -p "$PLACEHOLDER/docs/agents"
git -C "$PLACEHOLDER" init -b main >/dev/null 2>&1 || fail "git init failed"
cp "$TEMPLATE" "$PLACEHOLDER/docs/agents/verification.md"
STATUS=0
OUT="$("$SCRIPT" "$PLACEHOLDER" 2>/dev/null)" || STATUS=$?
[ "$STATUS" -eq 1 ] || fail "unedited template should be drift, got $STATUS: $OUT"
for kind in forge entrypoint port file; do
  echo "$OUT" | grep -q "DRIFT $kind: .*unfilled template placeholder" \
    || fail "unedited template did not flag the $kind placeholder: $OUT"
done

# --- malformed marker values are a document error, not a repo fact ---
UNSAFE="$TMP_DIR/unsafe"
cp -R "$REPO" "$UNSAFE"
cat > "$UNSAFE/docs/agents/verification.md" <<'DOC'
# Verification

<!-- drift:entrypoint /etc/passwd -->
<!-- drift:file ../../etc/hosts -->
<!-- drift:port eighty -->
DOC
STATUS=0
OUT="$("$SCRIPT" "$UNSAFE" 2>/dev/null)" || STATUS=$?
[ "$STATUS" -eq 1 ] || fail "malformed markers should be drift, got $STATUS: $OUT"
echo "$OUT" | grep -q "DRIFT entrypoint:.*not a repo-relative path" \
  || fail "absolute entrypoint path not rejected: $OUT"
echo "$OUT" | grep -q "DRIFT file:.*not a repo-relative path" \
  || fail "traversing file path not rejected: $OUT"
echo "$OUT" | grep -q "DRIFT port:.*not a number" \
  || fail "non-numeric port not rejected: $OUT"

# --- a repo has one origin, so two forge markers are a document error ---
TWOFORGE="$TMP_DIR/twoforge"
cp -R "$REPO" "$TWOFORGE"
printf '<!-- drift:forge gitlab -->\n' >> "$TWOFORGE/docs/agents/verification.md"
STATUS=0
OUT="$("$SCRIPT" "$TWOFORGE" 2>/dev/null)" || STATUS=$?
[ "$STATUS" -eq 1 ] || fail "two forge markers should be drift, got $STATUS: $OUT"
echo "$OUT" | grep -q "a repo has one origin" || fail "duplicate forge not reported: $OUT"

# --- a repo documented as having no forge, and having none, is clean ---
NOFORGE="$TMP_DIR/noforge"
cp -R "$REPO" "$NOFORGE"
git -C "$NOFORGE" remote remove origin
sed 's/drift:forge github/drift:forge none/' "$REPO/docs/agents/verification.md" \
  > "$NOFORGE/docs/agents/verification.md"
OUT="$("$SCRIPT" "$NOFORGE")" || fail "documented-none repo should exit 0: $OUT"
echo "$OUT" | grep -q "ok    forge: no remote, as documented" \
  || fail "documented-none branch not reported ok: $OUT"

# --- usage errors ---
if "$SCRIPT" --bogus "$REPO" >/dev/null 2>&1; then
  fail "unknown option should fail"
fi

BARE="$TMP_DIR/bare"
mkdir -p "$BARE"
STATUS=0
"$SCRIPT" "$BARE" >/dev/null 2>&1 || STATUS=$?
[ "$STATUS" -eq 2 ] || fail "repo without verification.md should exit 2, got $STATUS"

STATUS=0
"$SCRIPT" "$TMP_DIR/does-not-exist" >/dev/null 2>&1 || STATUS=$?
[ "$STATUS" -eq 2 ] || fail "missing directory should exit 2, got $STATUS"

echo "setup-agent-ready-repo-drift tests passed"
