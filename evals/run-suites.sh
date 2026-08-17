#!/usr/bin/env bash
set -euo pipefail

# Run one or more Waza eval suites.
# Usage: evals/run-suites.sh [--changed] [--baseline] [--print] [suite...]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

changed=0
baseline=0
print_only=0
requested=()

usage() {
  printf 'Usage: %s [--changed] [--baseline] [--print] [suite...]\n' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --changed) changed=1; shift ;;
    --baseline) baseline=1; shift ;;
    --print) print_only=1; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf 'unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ ! $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        printf 'invalid suite name: %s\n' "$1" >&2
        exit 2
      fi
      requested+=("$1")
      shift
      ;;
  esac
done

all_suites() {
  local spec
  for spec in evals/*/eval.yaml; do
    basename "$(dirname "$spec")"
  done | sort
}

suite_exists() {
  [[ -f "evals/$1/eval.yaml" ]]
}

suites_from_diff() {
  local files f name
  if ! git rev-parse --verify --quiet origin/main >/dev/null; then
    printf 'origin/main is missing; fetch it or pass suite names\n' >&2
    exit 2
  fi
  files=$(git diff --name-only origin/main...HEAD)
  if printf '%s\n' "$files" | grep -Eq \
    '^(\.github/workflows/waza-eval\.yml|\.waza\.yaml|mise\.toml|evals/run-suites\.sh)$'; then
    all_suites
    return
  fi
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    case $f in
      skills/*/* | evals/*/*)
        name=${f#*/}
        name=${name%%/*}
        if suite_exists "$name"; then
          printf '%s\n' "$name"
        fi
        ;;
    esac
  done <<<"$files" | sort -u
}

selected=()
if ((${#requested[@]} > 0)); then
  for name in "${requested[@]}"; do
    if ! suite_exists "$name"; then
      printf 'unknown suite: %s\n' "$name" >&2
      exit 2
    fi
    selected+=("$name")
  done
elif ((changed)); then
  mapfile -t selected < <(suites_from_diff)
else
  mapfile -t selected < <(all_suites)
fi

if ((${#selected[@]} == 0)); then
  printf 'no Waza suites to run\n'
  exit 0
fi

if ((print_only)); then
  printf '%s\n' "${selected[@]}"
  exit 0
fi

extra=()
if ((baseline)); then
  extra+=(--baseline)
fi

failed=0
mkdir -p waza-results
for name in "${selected[@]}"; do
  printf '==> %s\n' "$name"
  if ! waza run "evals/${name}/eval.yaml" \
    --output "waza-results/${name}.json" "${extra[@]}"; then
    failed=1
  fi
done
exit "$failed"
