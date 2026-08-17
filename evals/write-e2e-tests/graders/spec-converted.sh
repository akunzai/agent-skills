#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scan=""
for cand in \
  "$here/../../../skills/write-e2e-tests/scripts/scan-secrets.sh" \
  skills/write-e2e-tests/scripts/scan-secrets.sh; do
  if [[ -f $cand ]]; then
    scan=$(cd "$(dirname "$cand")" && pwd)/$(basename "$cand")
    break
  fi
done
if [[ -z $scan ]]; then
  echo "scan-secrets.sh not found" >&2
  exit 1
fi

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"

shopt -s nullglob
specs=(e2e/*.spec.ts e2e/*.spec.js e2e/*.spec.mjs e2e/*.spec.mts)
if ((${#specs[@]} == 0)); then
  echo "no Playwright spec under e2e/" >&2
  exit 1
fi

joined=$(cat "${specs[@]}")
for needle in expect Fixture\ Widgets Discount 90; do
  if [[ "$joined" != *"$needle"* ]]; then
    echo "generated spec is missing ${needle}" >&2
    exit 1
  fi
done

for spec in "${specs[@]}"; do
  bash "$scan" "$spec"
done

echo "converted spec passed static checks: ${specs[*]}"
