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

copilot_unavailable_result() {
  local result_file=$1

  # GitHub Actions installation auth may expose no account quota snapshot, so
  # classify Waza's own runtime result and fail closed otherwise.
  #
  # The only Copilot signal a result carries is the run's `error_msg`, and it is
  # prose, not a code: Waza stores `err.Error()` from the SDK, and the SDK turns
  # a session.error event into "session error: <human message>", dropping the
  # structured `errorCode` / `errorType` fields. So match the human wording and
  # keep the CAPI quota codes only as belt-and-braces for a future Waza that
  # surfaces them. `rate_limit` codes stay out on purpose: throttling is
  # transient and must not green-light a PR.
  # https://docs.github.com/en/copilot/how-tos/copilot-sdk/features/usage-and-billing
  # https://github.com/microsoft/waza/blob/v0.38.7/internal/execution/copilot.go#L536
  # https://github.com/github/copilot-sdk/blob/v1.0.11/go/session.go#L504
  # https://github.com/github/copilot-sdk/blob/v1.0.11/go/rpc/zsession_events.go#L706
  [[ -s $result_file ]] || return 1
  jq -e '
    def copilot_unavailable:
      test(
        "quota_exceeded|session_quota_exceeded|billing_not_configured"
        + "|(quota|allowance|premium request)[^.\n]*"
        + "(exceed|exhaust|reach|used up|unavailable|limit)"
        + "|(exceed|exhaust|reach|run out of|no more|no)[^.\n]*"
        + "(quota|allowance|premium request)"
        + "|billing[^.\n]*(not configured|required|unavailable)"
        + "|subscription[^.\n]*(required|missing|inactive|expired|not active)";
        "i"
      );

    def unavailable_run:
      .status == "error" and ((.error_msg // "") | copilot_unavailable);

    [(.tasks // [])[].runs[]] as $runs
    | any($runs[]; unavailable_run)
      and all($runs[]; .status == "passed" or unavailable_run)
  ' "$result_file" >/dev/null 2>&1
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
  result_file="waza-results/${name}.json"
  if ! waza run "evals/${name}/eval.yaml" \
    --output "$result_file" "${extra[@]}"; then
    if ((failed == 0)) && copilot_unavailable_result "$result_file"; then
      message="Copilot quota or subscription is unavailable; skipping remaining Waza suites."
      if [[ ${GITHUB_ACTIONS:-} == true ]]; then
        printf '::warning::%s\n' "$message"
      else
        printf '%s\n' "$message" >&2
      fi
      exit 0
    fi
    failed=1
  fi
done
exit "$failed"
