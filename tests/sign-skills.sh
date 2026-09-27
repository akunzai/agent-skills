#!/usr/bin/env bash
set -euo pipefail

# Runs scripts/sign-skills.sh in --key mode against a scratch repository:
# it signs every Skill once, leaves a still-valid signature alone, re-signs
# only the Skill whose content changed, and the result verifies with the
# reference model_signing CLI.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/sign-skills.sh"
MODEL_SIGNING_VERSION="$(sed -n 's/^MODEL_SIGNING_VERSION="\(.*\)"$/\1/p' "$SCRIPT")"

fail() {
  echo "sign-skills test failed: $*" >&2
  exit 1
}

command -v uvx >/dev/null || fail "uvx is required (mise install provides uv)"
command -v openssl >/dev/null || fail "openssl is required"
[ -n "$MODEL_SIGNING_VERSION" ] || fail "MODEL_SIGNING_VERSION not found in $SCRIPT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO/skills/alpha/references" "$REPO/skills/beta" "$REPO/plugins/p/skills/gamma"
printf -- '---\nname: alpha\ndescription: Alpha.\n---\n' > "$REPO/skills/alpha/SKILL.md"
printf 'reference\n' > "$REPO/skills/alpha/references/r.md"
printf -- '---\nname: beta\ndescription: Beta.\n---\n' > "$REPO/skills/beta/SKILL.md"
# A plugin Skill ships through its plugin, whose installers never verify it.
printf -- '---\nname: gamma\ndescription: Gamma.\n---\n' > "$REPO/plugins/p/skills/gamma/SKILL.md"

openssl ecparam -name prime256v1 -genkey -noout -out "$TMP_DIR/key.pem" 2>/dev/null
openssl ec -in "$TMP_DIR/key.pem" -pubout -out "$TMP_DIR/key.pub" 2>/dev/null

run() {
  bash "$SCRIPT" --key "$TMP_DIR/key.pem" "$TMP_DIR/key.pub" "$REPO"
}

expected_first="signed skills/alpha
signed skills/beta"
out="$(run)" || fail "first run exited non-zero"
[ "$out" = "$expected_first" ] || fail "first run: expected
$expected_first
got
$out"
[ -f "$REPO/skills/alpha/skill.oms.sig" ] || fail "skills/alpha/skill.oms.sig missing"
[ ! -e "$REPO/plugins/p/skills/gamma/skill.oms.sig" ] || fail "a plugin Skill should not be signed"

out="$(run)" || fail "second run exited non-zero"
[ "$out" = "unchanged skills/alpha
unchanged skills/beta" ] || fail "second run should leave valid signatures alone, got
$out"

printf 'changed\n' >> "$REPO/skills/alpha/references/r.md"
out="$(run)" || fail "third run exited non-zero"
[ "$out" = "signed skills/alpha
unchanged skills/beta" ] || fail "third run should re-sign only skills/alpha, got
$out"

uvx -q --from "model-signing==$MODEL_SIGNING_VERSION" model_signing verify key "$REPO/skills/alpha" \
  --signature "$REPO/skills/alpha/skill.oms.sig" --public_key "$TMP_DIR/key.pub" >/dev/null \
  || fail "reference verifier rejected the re-signed skill"

printf 'unsigned\n' > "$REPO/skills/alpha/extra.txt"
if uvx -q --from "model-signing==$MODEL_SIGNING_VERSION" model_signing verify key "$REPO/skills/alpha" \
  --signature "$REPO/skills/alpha/skill.oms.sig" --public_key "$TMP_DIR/key.pub" >/dev/null 2>&1; then
  fail "an extra unsigned file should fail strict verification"
fi

if GITHUB_WORKFLOW_REF="" bash "$SCRIPT" "$REPO" >/dev/null 2>&1; then
  fail "Sigstore mode without GITHUB_WORKFLOW_REF should exit non-zero"
fi

echo "sign-skills tests passed"
