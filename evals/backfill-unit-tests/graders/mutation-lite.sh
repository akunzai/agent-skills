#!/usr/bin/env bash
set -euo pipefail

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"
export PYTHONDONTWRITEBYTECODE=1

if [[ ! -f pricing.py ]]; then
  echo "pricing.py missing" >&2
  exit 1
fi

if ! python3 -m unittest discover -s tests -t . -v; then
  echo "generated tests do not pass on the original implementation" >&2
  exit 1
fi

cp pricing.py pricing.py.bak
cleanup() {
  mv -f pricing.py.bak pricing.py
}
trap cleanup EXIT

break_fn() {
  local old=$1
  local new=$2
  local label=$3
  if ! grep -Fq "$old" pricing.py; then
    echo "could not locate ${label} return for mutation" >&2
    exit 1
  fi
  python3 - "$old" "$new" <<'PY'
import sys
from pathlib import Path

old, new = sys.argv[1], sys.argv[2]
path = Path("pricing.py")
path.write_text(path.read_text().replace(old, new, 1), encoding="utf-8")
PY
  rm -rf __pycache__ tests/__pycache__
  if python3 -m unittest discover -s tests -t . -v; then
    echo "mutation-lite: tests still passed after breaking ${label}" >&2
    exit 1
  fi
  mv -f pricing.py.bak pricing.py
  cp pricing.py pricing.py.bak
}

break_fn \
  "return price * (100 - percent) // 100" \
  "return price * (100 + percent) // 100" \
  "apply_discount"

break_fn \
  "return net * (100 + rate) // 100" \
  "return net * (100 - rate) // 100" \
  "tax_inclusive"

echo "mutation-lite: tests failed after breaking apply_discount and tax_inclusive"
