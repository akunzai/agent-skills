#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT_DIR/evals/run-suites.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

fixture_root="$TMP_DIR/repo"
fake_bin="$TMP_DIR/bin"
mkdir -p "$fixture_root/evals/agents-md" "$fixture_root/evals/pr-workflow" "$fake_bin"
cp "$RUN" "$fixture_root/evals/run-suites.sh"
touch "$fixture_root/evals/agents-md/eval.yaml"
touch "$fixture_root/evals/pr-workflow/eval.yaml"

cat >"$fake_bin/waza" <<'FAKE_WAZA'
#!/usr/bin/env bash
set -euo pipefail

output=""
spec=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --output)
      output=$2
      shift 2
      ;;
    *eval.yaml)
      spec=$1
      shift
      ;;
    *) shift ;;
  esac
done

case ${FAKE_WAZA_MODE:-pass} in
  quota)
    printf '%s\n' '{
      "tasks": [{
        "runs": [
          {"status": "passed"},
          {"status": "error", "error_msg": "session error: You have exceeded your premium request allowance for this billing cycle."}
        ]
      }]
    }' >"$output"
    exit 1
    ;;
  quota-code)
    printf '%s\n' '{
      "tasks": [{"runs": [{"status": "error", "error_msg": "quota_exceeded"}]}]
    }' >"$output"
    exit 1
    ;;
  subscription)
    printf '%s\n' '{
      "tasks": [{
        "runs": [{
          "status": "error",
          "error_msg": "session error: Your Copilot subscription is inactive."
        }]
      }]
    }' >"$output"
    exit 1
    ;;
  rate-limit)
    printf '%s\n' '{
      "tasks": [{
        "runs": [{
          "status": "error",
          "error_msg": "session error: You have been rate limited. Try again later."
        }]
      }]
    }' >"$output"
    exit 1
    ;;
  no-result)
    exit 2
    ;;
  empty-result)
    : >"$output"
    exit 2
    ;;
  grader)
    printf '%s\n' '{
      "tasks": [{"runs": [{"status": "failed", "error_msg": "grader mismatch"}]}]
    }' >"$output"
    exit 1
    ;;
  mixed)
    printf '%s\n' '{
      "tasks": [{
        "runs": [
          {"status": "error", "error_msg": "session error: premium request quota exceeded"},
          {"status": "failed", "error_msg": "grader mismatch"}
        ]
      }]
    }' >"$output"
    exit 1
    ;;
  runtime)
    printf '%s\n' '{
      "tasks": [{"runs": [{"status": "error", "error_msg": "network timeout"}]}]
    }' >"$output"
    exit 2
    ;;
  across-suites)
    if [[ $spec == *pr-workflow* ]]; then
      printf '%s\n' '{
        "tasks": [{"runs": [{"status": "failed", "error_msg": "grader mismatch"}]}]
      }' >"$output"
    else
      printf '%s\n' '{
        "tasks": [{
          "runs": [{"status": "error", "error_msg": "session error: premium request quota exceeded"}]
        }]
      }' >"$output"
    fi
    exit 1
    ;;
esac
FAKE_WAZA
chmod +x "$fake_bin/waza"

run_fake() {
  local mode=$1
  local expected=$2
  local output

  # a stale result from an earlier mode would answer for the one under test
  rm -rf "$fixture_root/waza-results"

  set +e
  output=$(FAKE_WAZA_MODE=$mode PATH="$fake_bin:$PATH" \
    "$fixture_root/evals/run-suites.sh" pr-workflow 2>&1)
  status=$?
  set -e

  [ "$status" -eq "$expected" ] \
    || fail "$mode result should exit $expected, got $status"
  printf '%s\n' "$output"
}

quota_output=$(run_fake quota 0)
printf '%s\n' "$quota_output" | grep -q 'skipping remaining Waza suites' \
  || fail "quota-only error should explain that remaining suites were skipped"
run_fake quota-code 0 >/dev/null
run_fake subscription 0 >/dev/null
run_fake grader 1 >/dev/null
run_fake mixed 1 >/dev/null
run_fake runtime 1 >/dev/null
# throttling is transient, and a result Waza never wrote says nothing at all
run_fake rate-limit 1 >/dev/null
run_fake no-result 1 >/dev/null
run_fake empty-result 1 >/dev/null

set +e
FAKE_WAZA_MODE=across-suites PATH="$fake_bin:$PATH" \
  "$fixture_root/evals/run-suites.sh" pr-workflow agents-md >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] \
  || fail "a later quota error must not hide an earlier grader failure"

echo "waza run-suites checks passed"
