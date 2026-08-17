#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT_DIR/evals/run-suites.sh"

fail() {
  echo "waza run-suites check failed: $*" >&2
  exit 1
}

[ -x "$RUN" ] || fail "evals/run-suites.sh is missing or not executable"

listed=$("$RUN" --print)
printf '%s\n' "$listed" | grep -qx 'pr-workflow' \
  || fail "expected pr-workflow in the full suite list"

set +e
"$RUN" --print nosuch-suite >/dev/null 2>/dev/null
status=$?
set -e
[ "$status" -eq 2 ] || fail "unknown suite should exit 2, got $status"

echo "waza run-suites checks passed"
