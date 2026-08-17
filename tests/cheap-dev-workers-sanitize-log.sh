#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/cheap-dev-workers/scripts/sanitize-log.sh"

fail() {
  echo "cheap-dev-workers sanitize-log check failed: $*" >&2
  exit 1
}

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
bin="$fixture_root/bin"
task_tmp="$fixture_root/tmp"
mkdir -p "$bin" "$task_tmp"
printf 'filter = "true"\n' >"$task_tmp/.betterleaks.toml"
printf 'filter = "true"\n' >"$task_tmp/.gitleaks.toml"

cat >"$bin/redact" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '--format text anonymize --strategy replace' ]] || exit 64
if [[ "${FAKE_REDACT_FAIL:-}" == 1 ]]; then
  echo 'redactor leaked SECRET_VALUE' >&2
  exit 1
fi
sed 's/SECRET_VALUE/[REDACTED]/g'
EOF
cat >"$bin/betterleaks" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == dir && -f "${2:-}" ]] || exit 64
[[ -z "${BETTERLEAKS_CONFIG:-}" ]] || exit 65
[[ ! -e "$(dirname "$2")/.betterleaks.toml" ]] || exit 66
[[ ! -e "$(dirname "$2")/.gitleaks.toml" ]] || exit 67
if [[ "${FAKE_BETTERLEAKS_FAIL:-}" == 1 ]]; then
  echo 'unsafe scanner report: SECRET_VALUE' >&2
  exit 2
fi
if grep -q 'RESIDUAL_VALUE' "$2"; then
  echo 'unsafe finding: RESIDUAL_VALUE' >&2
  exit 1
fi
EOF
chmod +x "$bin/redact" "$bin/betterleaks"

raw="$fixture_root/raw.log"
safe="$fixture_root/safe.log"
capture="$fixture_root/capture"
printf 'filter = "true"\n' >"$fixture_root/.betterleaks.toml"
printf 'build failed token=SECRET_VALUE\n' >"$raw"
BETTERLEAKS_CONFIG="$fixture_root/untrusted.toml" TMPDIR="$task_tmp" \
  PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >"$capture" 2>&1 \
  || fail "safe UTF-8 fixture was rejected"
grep -q '\[REDACTED\]' "$safe" || fail "sanitized replacement is missing"
! grep -q 'SECRET_VALUE' "$safe" "$capture" || fail "raw secret crossed the output boundary"

printf 'RESIDUAL_VALUE\n' >"$raw"
rm -f "$safe"
if PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >"$capture" 2>&1; then
  fail "residual finding should fail closed"
fi
[[ ! -e "$safe" ]] || fail "failed residual scan left a worker-readable artifact"
! grep -q 'RESIDUAL_VALUE' "$capture" || fail "scanner finding leaked into model-visible output"

printf 'SECRET_VALUE\n' >"$raw"
if FAKE_REDACT_FAIL=1 PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >"$capture" 2>&1; then
  fail "redactor failure should fail closed"
fi
! grep -q 'SECRET_VALUE' "$capture" || fail "redactor failure output crossed the boundary"

if FAKE_BETTERLEAKS_FAIL=1 PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >"$capture" 2>&1; then
  fail "scanner failure should fail closed"
fi
! grep -q 'SECRET_VALUE' "$capture" || fail "unsafe scanner report crossed the boundary"

printf '\xff\xfe' >"$raw"
if PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >/dev/null 2>&1; then
  fail "unknown encoding should be rejected"
fi

dd if=/dev/zero bs=1048576 count=10 status=none | tr '\000' x >"$raw"
PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >/dev/null 2>&1 \
  || fail "exactly 10 MiB of UTF-8 text should be accepted"
printf x >>"$raw"
if PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >"$capture" 2>&1; then
  fail "input above 10 MiB should be rejected"
fi
grep -q 'split it at job or test-suite boundaries' "$capture" \
  || fail "oversized input lacks semantic-splitting guidance"

printf 'ok\0binary' >"$raw"
if PATH="$bin:/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >/dev/null 2>&1; then
  fail "binary input should be rejected"
fi

printf 'ordinary log\n' >"$raw"
if PATH="/usr/bin:/bin" "$SCRIPT" "$raw" "$safe" >/dev/null 2>&1; then
  fail "missing hardening tools should not silently downgrade"
fi

echo "cheap-dev-workers sanitize-log checks passed"
