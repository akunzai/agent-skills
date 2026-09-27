#!/usr/bin/env bash
set -euo pipefail

# Signs every catalog Skill directory (skills/*) with an OpenSSF Model
# Signing (OMS) detached signature at <skill>/skill.oms.sig. Plugin Skills
# are not signed: plugin installers never read the signature, and those
# Skills only work inside their plugin.
# A Skill whose existing signature still verifies is left alone, so the run
# is idempotent and a re-run after a merge only touches what changed.
#
# Default mode is Sigstore keyless, for .github/workflows/sign-skills.yml:
# the signer is the workflow's own GitHub OIDC identity. --key signs and
# verifies with a local EC key pair instead, so tests/sign-skills.sh runs
# offline.
#
# Prints one line per Skill: "unchanged <dir>" or "signed <dir>".

MODEL_SIGNING_VERSION="1.1.1"
SIGSTORE_ISSUER="https://token.actions.githubusercontent.com"

usage() {
  cat >&2 <<'USAGE'
usage: sign-skills.sh [--key PRIVATE_PEM PUBLIC_PEM] [ROOT]

  --key   sign with a local EC key pair instead of Sigstore keyless
  ROOT    repository root (default: this script's repository)
USAGE
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_KEY=""
PUBLIC_KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --key)
      [ $# -ge 3 ] || { usage; exit 2; }
      PRIVATE_KEY="$2"
      PUBLIC_KEY="$3"
      shift 3
      ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 2 ;;
    *) ROOT_DIR="$1"; shift ;;
  esac
done

model_signing() {
  if [ -n "${MODEL_SIGNING_CMD:-}" ]; then
    "$MODEL_SIGNING_CMD" "$@"
  else
    uvx -q --from "model-signing==$MODEL_SIGNING_VERSION" model_signing "$@"
  fi
}

if [ -z "$PRIVATE_KEY" ]; then
  # GITHUB_WORKFLOW_REF is owner/repo/.github/workflows/<file>@<ref>, which
  # is the certificate identity Fulcio issues to the workflow.
  [ -n "${GITHUB_WORKFLOW_REF:-}" ] \
    || { echo "sign-skills: Sigstore mode needs GITHUB_WORKFLOW_REF (run in GitHub Actions, or pass --key)" >&2; exit 2; }
  IDENTITY="https://github.com/$GITHUB_WORKFLOW_REF"
fi

verify() {
  if [ -n "$PRIVATE_KEY" ]; then
    model_signing verify key "$1" --signature "$1/skill.oms.sig" --public_key "$PUBLIC_KEY"
  else
    model_signing verify sigstore "$1" --signature "$1/skill.oms.sig" \
      --identity "$IDENTITY" --identity_provider "$SIGSTORE_ISSUER"
  fi
}

sign() {
  if [ -n "$PRIVATE_KEY" ]; then
    model_signing sign key "$1" --signature "$1/skill.oms.sig" --private_key "$PRIVATE_KEY"
  else
    model_signing sign sigstore "$1" --signature "$1/skill.oms.sig" --use_ambient_credentials
  fi
}

found=0
while IFS= read -r skill_md; do
  found=$((found + 1))
  dir="$(dirname "$skill_md")"
  rel="${dir#"$ROOT_DIR"/}"
  if [ -f "$dir/skill.oms.sig" ] && verify "$dir" >/dev/null 2>&1; then
    echo "unchanged $rel"
    continue
  fi
  sign "$dir" >/dev/null
  verify "$dir" >/dev/null || { echo "sign-skills: $rel does not verify right after signing" >&2; exit 1; }
  echo "signed $rel"
done < <(find "$ROOT_DIR/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | sort)

[ "$found" -gt 0 ] || { echo "sign-skills: no SKILL.md found under $ROOT_DIR" >&2; exit 1; }
