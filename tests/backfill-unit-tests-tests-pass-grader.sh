#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/evals/backfill-unit-tests/graders/tests-pass.sh"

fail() {
  echo "backfill-unit-tests tests-pass grader check failed: $*" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is not on PATH"
[ -f "$SCRIPT" ] || fail "$SCRIPT is missing"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- a workspace with a passing test that mentions both required functions
# is graded pass, under bash 5 and explicitly under macOS's stock /bin/bash
# 3.2. The grader used `mapfile`, a bash 4+ builtin absent from 3.2, so this
# is the regression guard for that gap. ---
WS="$TMP_DIR/ws"
mkdir -p "$WS/tests"
touch "$WS/tests/__init__.py"
cat >"$WS/tests/test_pricing.py" <<'PY'
import unittest


def apply_discount(price, pct):
    return price * (1 - pct)


def tax_inclusive(price, rate):
    return price * (1 + rate)


class PricingTests(unittest.TestCase):
    def test_apply_discount(self):
        self.assertAlmostEqual(apply_discount(100, 0.1), 90)

    def test_tax_inclusive(self):
        self.assertAlmostEqual(tax_inclusive(100, 0.1), 110)
PY

for interpreter in bash /bin/bash; do
  STATUS=0
  OUT="$(WAZA_WORKSPACE_DIR="$WS" "$interpreter" "$SCRIPT" 2>&1)" || STATUS=$?
  [ "$STATUS" -eq 0 ] \
    || fail "$interpreter grader should pass a workspace with both required tests: $OUT"
  case "$OUT" in
    *OK*) ;;
    *) fail "$interpreter grader did not report the unittest run as OK: $OUT" ;;
  esac
done

# --- a workspace with no tests/test_*.py files fails, not crashes ---
EMPTY_WS="$TMP_DIR/empty-ws"
mkdir -p "$EMPTY_WS/tests"
STATUS=0
OUT="$(WAZA_WORKSPACE_DIR="$EMPTY_WS" /bin/bash "$SCRIPT" 2>&1)" || STATUS=$?
[ "$STATUS" -eq 1 ] \
  || fail "an empty tests/ directory should exit 1 under /bin/bash, got $STATUS: $OUT"
case "$OUT" in
  *"no tests/test_*.py files"*) ;;
  *) fail "empty workspace did not report the missing test files: $OUT" ;;
esac

# --- a workspace missing the required functions fails ---
MISSING_WS="$TMP_DIR/missing-ws"
mkdir -p "$MISSING_WS/tests"
touch "$MISSING_WS/tests/__init__.py"
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_noop(self):\n        pass\n' \
  >"$MISSING_WS/tests/test_noop.py"
STATUS=0
OUT="$(WAZA_WORKSPACE_DIR="$MISSING_WS" /bin/bash "$SCRIPT" 2>&1)" || STATUS=$?
[ "$STATUS" -eq 1 ] \
  || fail "tests missing apply_discount/tax_inclusive should exit 1 under /bin/bash, got $STATUS: $OUT"
case "$OUT" in
  *"do not mention apply_discount and tax_inclusive"*) ;;
  *) fail "missing-function workspace did not name the missing functions: $OUT" ;;
esac

echo "backfill-unit-tests tests-pass grader checks passed"
