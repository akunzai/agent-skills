#!/usr/bin/env bash
set -euo pipefail

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"
export PYTHONDONTWRITEBYTECODE=1

if [[ ! -d tests ]]; then
  echo "tests/ directory missing" >&2
  exit 1
fi

mapfile -t tests < <(find tests -name 'test_*.py' -type f)
if ((${#tests[@]} == 0)); then
  echo "no tests/test_*.py files in the workspace" >&2
  exit 1
fi

joined=$(cat "${tests[@]}")
if [[ "$joined" != *apply_discount* ]] || [[ "$joined" != *tax_inclusive* ]]; then
  echo "tests do not mention apply_discount and tax_inclusive" >&2
  exit 1
fi

python3 -m unittest discover -s tests -t . -v
