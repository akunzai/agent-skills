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

# evals/run-suites.sh used `mapfile`, a bash 4+ builtin absent from macOS's
# stock /bin/bash 3.2; pin the interpreter explicitly so this does not
# silently pass by picking up a newer `bash` from PATH.
listed_sysbash=$(/bin/bash "$RUN" --print)
[ "$listed_sysbash" = "$listed" ] \
  || fail "/bin/bash --print produced different suites than bash: $listed_sysbash"

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
printf 'waza-results/\n' >"$fixture_root/.gitignore"
printf 'original\n' >"$fixture_root/AGENTS.md"
git -C "$fixture_root" init -q
git -C "$fixture_root" add -A
git -C "$fixture_root" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m fixture

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
  escape)
    # an agent writing to the checkout by absolute path, then passing
    printf 'mise trust\n' >>"$FAKE_WAZA_CHECKOUT/AGENTS.md"
    printf 'note\n' >"$FAKE_WAZA_CHECKOUT/escaped.md"
    printf '%s\n' '{"tasks": [{"runs": [{"status": "passed"}]}]}' >"$output"
    ;;
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

# --- a suite that writes to the checkout fails even when its graders pass,
# and names what it wrote; edits already in the tree before the run do not
# count, but a further write to an already-modified file does. ---
escape_run() {
  rm -rf "$fixture_root/waza-results" "$fixture_root/escaped.md"
  git -C "$fixture_root" checkout -q -- AGENTS.md
  [ -z "${1:-}" ] || printf '%s\n' "$1" >>"$fixture_root/AGENTS.md"
  set +e
  escape_out=$(FAKE_WAZA_MODE=$2 FAKE_WAZA_CHECKOUT=$fixture_root \
    PATH="$fake_bin:$PATH" "$fixture_root/evals/run-suites.sh" pr-workflow 2>&1)
  escape_status=$?
  set -e
}

escape_run '' escape
[ "$escape_status" -eq 1 ] \
  || fail "a suite writing to the checkout should exit 1, got $escape_status"
printf '%s\n' "$escape_out" | grep -q 'pr-workflow wrote outside its Waza workspace' \
  || fail "the escape should name the suite: $escape_out"
printf '%s\n' "$escape_out" | grep -q 'M.*AGENTS.md' \
  || fail "the escape should list the modified file: $escape_out"
printf '%s\n' "$escape_out" | grep -q 'A.*escaped.md' \
  || fail "the escape should list the new untracked file: $escape_out"

escape_run 'local edit' pass
[ "$escape_status" -eq 0 ] \
  || fail "an edit made before the run should not count, got $escape_status: $escape_out"

escape_run 'local edit' escape
[ "$escape_status" -eq 1 ] \
  || fail "a write to an already-modified file should still fail, got $escape_status"
git -C "$fixture_root" checkout -q -- AGENTS.md
rm -f "$fixture_root/escaped.md"

# --- the empty `${extra[@]}` expansion (only populated by --baseline)
# crashed /bin/bash 3.2 under `set -u`; run both the empty and populated
# paths explicitly under it. ---
rm -rf "$fixture_root/waza-results"
set +e
sysbash_out=$(FAKE_WAZA_MODE=pass PATH="$fake_bin:$PATH" \
  /bin/bash "$fixture_root/evals/run-suites.sh" pr-workflow 2>&1)
sysbash_status=$?
set -e
[ "$sysbash_status" -eq 0 ] \
  || fail "/bin/bash run with no --extra flags should exit 0, got $sysbash_status: $sysbash_out"

rm -rf "$fixture_root/waza-results"
set +e
sysbash_baseline_out=$(FAKE_WAZA_MODE=pass PATH="$fake_bin:$PATH" \
  /bin/bash "$fixture_root/evals/run-suites.sh" --baseline pr-workflow 2>&1)
sysbash_baseline_status=$?
set -e
[ "$sysbash_baseline_status" -eq 0 ] \
  || fail "/bin/bash --baseline run should exit 0, got $sysbash_baseline_status: $sysbash_baseline_out"

echo "waza run-suites checks passed"
