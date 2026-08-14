#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/write-e2e-tests/scripts/scan-secrets.sh"

fail() {
  echo "write-e2e-tests scan-secrets check failed: $*" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "scripts/scan-secrets.sh is missing or not executable"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_scan() {
  local file=$1
  set +e
  SCAN_OUT="$("$SCRIPT" "$file" 2>"$TMP_DIR/stderr")"
  SCAN_STATUS=$?
  set -e
}

assert_hit() {
  local category=$1
  local line=$2
  printf '%s\n' "$SCAN_OUT" | grep -qx "${SCAN_FILE}:${line}:${category}" \
    || fail "expected ${SCAN_FILE}:${line}:${category} in:$SCAN_OUT"
}

# usage / missing file
set +e
"$SCRIPT" >/dev/null 2>"$TMP_DIR/stderr"
status=$?
set -e
[ "$status" -eq 2 ] || fail "no-args should exit 2, got $status"

set +e
"$SCRIPT" "$TMP_DIR/missing.py" >/dev/null 2>"$TMP_DIR/stderr"
status=$?
set -e
[ "$status" -eq 2 ] || fail "missing file should exit 2, got $status"

# clean input: selectors, env fills, non-credential fixtures
SCAN_FILE="$TMP_DIR/clean.spec.ts"
cat >"$SCAN_FILE" <<'EOF'
import { test, expect } from '@playwright/test';

test('login form', async ({ page }) => {
  await page.getByLabel('Password').click();
  await page.locator('input[type="password"]').click();
  await page.getByLabel('Password').fill(process.env.E2E_USER_PASSWORD);
  await page.fill('#password', process.env.E2E_USER_PASSWORD);
  await page.getByLabel('Email').fill('user@example.com');
  const password = page.getByLabel('Password');
  await password.fill(process.env.E2E_USER_PASSWORD);
});
EOF

run_scan "$SCAN_FILE"
[ "$SCAN_STATUS" -eq 0 ] || fail "clean spec should exit 0, got $SCAN_STATUS out=$SCAN_OUT"
[ -z "$SCAN_OUT" ] || fail "clean spec should print nothing, got: $SCAN_OUT"

# hits: high-confidence shapes + credential field literals
SECRET_OPENAI='sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD'
SECRET_GITHUB='ghp_abcdefghijklmnopqrstuvwxyz012345'
SECRET_AWS='AKIAIOSFODNN7EXAMPLE'
SECRET_BEARER='Bearer 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'
SECRET_CONN='postgres://appuser:hunter2supersecret@db.internal:5432/app'
SECRET_PASSWORD='supersecret_value_xyz'
SECRET_FILL='hunter2_literal_password'

SCAN_FILE="$TMP_DIR/dirty.py"
cat >"$SCAN_FILE" <<EOF
# 1 openai
api_key = "${SECRET_OPENAI}"
# 2 github
token = "${SECRET_GITHUB}"
# 3 aws
aws_key = "${SECRET_AWS}"
# 4 pem
-----BEGIN RSA PRIVATE KEY-----
# 5 bearer
headers = {"Authorization": "${SECRET_BEARER}"}
# 6 connection
db = "${SECRET_CONN}"
# 7 assignment
password = "${SECRET_PASSWORD}"
# 8 chained fill
page.get_by_label("Password").fill("${SECRET_FILL}")
# 9 two-arg fill
page.fill("#password", "${SECRET_FILL}")
# 10 type + options
page.getByLabel("Password").type("${SECRET_FILL}", { delay: 10 })
# 11 github_pat
auth = "github_pat_abcdefghijklmnopqrstuvwxyz0123456789ABCD"
# 12 gho
old = "gho_abcdefghijklmnopqrstuvwxyz0123"
# 13 selector only — not a hit
page.get_by_label("Password")
# 14 env fill on a password field — not a hit
page.fill("#password", process.env.E2E_USER_PASSWORD)
EOF

run_scan "$SCAN_FILE"
[ "$SCAN_STATUS" -eq 1 ] || fail "dirty script should exit 1, got $SCAN_STATUS"

assert_hit openai_key 2
assert_hit credential_assignment 2
assert_hit github_token 4
assert_hit credential_assignment 4
assert_hit aws_access_key 6
assert_hit pem_private_key 8
assert_hit bearer_token 10
assert_hit connection_string 12
assert_hit credential_assignment 14
assert_hit password_field_literal 16
assert_hit password_field_literal 18
assert_hit password_field_literal 20
assert_hit github_token 22
assert_hit github_token 24

printf '%s\n' "$SCAN_OUT" | grep -E ':(26|28):' \
  && fail "selector-only or env-fill line must not hit: $SCAN_OUT"

# report must not leak literals
for secret in \
  "$SECRET_OPENAI" \
  "$SECRET_GITHUB" \
  "$SECRET_AWS" \
  "$SECRET_BEARER" \
  "$SECRET_CONN" \
  "$SECRET_PASSWORD" \
  "$SECRET_FILL"
do
  printf '%s\n' "$SCAN_OUT" | grep -F -q -- "$secret" \
    && fail "stdout leaked secret material: $secret"
done

# output format is only file:line:category
while IFS= read -r row; do
  [ -n "$row" ] || continue
  printf '%s\n' "$row" | grep -E -q "^${SCAN_FILE}:[0-9]+:[a-z_]+$" \
    || fail "unexpected report row: $row"
done <<<"$SCAN_OUT"

echo "write-e2e-tests scan-secrets checks passed"
