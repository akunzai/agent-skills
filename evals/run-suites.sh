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
  # mapfile is bash 4+; macOS ships /bin/bash 3.2, so read the suite names
  # one at a time instead.
  while IFS= read -r name; do
    [[ -n $name ]] && selected+=("$name")
  done < <(suites_from_diff)
else
  while IFS= read -r name; do
    [[ -n $name ]] && selected+=("$name")
  done < <(all_suites)
fi

if ((${#selected[@]} == 0)); then
  printf 'no Waza suites to run\n'
  exit 0
fi

if ((print_only)); then
  printf '%s\n' "${selected[@]}"
  exit 0
fi

notice() {
  if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    printf '::warning::%s\n' "$1"
  else
    printf '%s\n' "$1" >&2
  fi
}

# Waza's copilot-sdk executor sends sessions to a custom provider when
# COPILOT_BASE_URL is set, so no Copilot login or subscription is used.
# Without a key (a fork or Dependabot PR, or a local checkout that never set
# one) there is nothing to run against.
if [[ -z ${OPENROUTER_API_KEY:-} ]]; then
  notice "OPENROUTER_API_KEY is not set; skipping Waza suites."
  exit 0
fi
export COPILOT_BASE_URL=https://openrouter.ai/api/v1
export COPILOT_PROVIDER=openai
export COPILOT_API_KEY=$OPENROUTER_API_KEY

extra=()
if ((baseline)); then
  extra+=(--baseline)
fi

# Tasks run in an isolated Waza workspace, but an agent can still write to this
# checkout by absolute path (to-memory did, #273). The graders only read the
# workspace, so they report a missing pattern rather than the escape. Hash the
# whole tree, untracked files included, before and after each suite.
checkout_tree() {
  local index
  index=$(mktemp)
  cp "$(git rev-parse --git-path index)" "$index"
  GIT_INDEX_FILE=$index git add -A .
  GIT_INDEX_FILE=$index git write-tree
  rm -f "$index"
}

# One attempt of one suite: 0 passed, 1 failed, 2 wrote outside its
# workspace.
run_attempt() {
  local name=$1 result_file=$2 before after status=0
  before=$(checkout_tree)
  waza run "evals/${name}/eval.yaml" \
    --output "$result_file" ${extra[@]+"${extra[@]}"} || status=$?
  after=$(checkout_tree)
  if [[ $before != "$after" ]]; then
    printf '%s wrote outside its Waza workspace:\n' "$name" >&2
    git diff --name-status "$before" "$after" >&2
    return 2
  fi
  if ((status == 0)); then
    return 0
  fi
  return 1
}

failed=0
mkdir -p waza-results
for name in "${selected[@]}"; do
  printf '==> %s\n' "$name"
  result_file="waza-results/${name}.json"
  outcome=0
  run_attempt "$name" "$result_file" || outcome=$?
  # A single model run is noisy: a suite that fails its graders gets one more
  # attempt, and fails only if that one fails too. An escape is not noise,
  # so it is never retried.
  if ((outcome == 1)); then
    mv "$result_file" "waza-results/${name}.attempt1.json"
    printf '%s failed; retrying once\n' "$name" >&2
    outcome=0
    run_attempt "$name" "$result_file" || outcome=$?
    if ((outcome == 0)); then
      notice "$name passed on retry; waza-results/${name}.attempt1.json holds the failed attempt."
    fi
  fi
  ((outcome == 0)) || failed=1
done
exit "$failed"
