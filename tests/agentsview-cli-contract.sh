#!/usr/bin/env bash
set -euo pipefail

# Contract check for the AgentsView CLI surface cited by the agentsview-*
# skills. Parses every `agentsview ...` command written in those files and
# verifies the subcommand and its long flags still exist in the installed
# CLI's --help output.
#
# Run it via `mise run test-agentsview-contract`, which pins and supplies
# the CLI. Note that `agentsview <unknown-subcommand> --help` exits 0 and
# prints the PARENT's help, so exit codes alone prove nothing — every
# check below matches the Usage line to confirm the subcommand resolved.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCES=(
  "$ROOT_DIR/skills/agentsview-resume/SKILL.md"
  "$ROOT_DIR/skills/agentsview-resume/references/security.md"
  "$ROOT_DIR/skills/agentsview-extract/SKILL.md"
)

# Flags the skills name in prose rather than in a full command line, mapped
# to the subcommand they belong to.
PROSE_FLAGS=(
  "session messages:--around"
  "session search:--exclude-system"
  "session search:--reveal"
  "skills install:--force"
)

# Long flags in those files that belong to other tools, not to agentsview.
FOREIGN_FLAGS=(
  "--bin"     # uv tool dir --bin
  "--repo"    # gh pr view --repo
  "--resume"  # claude --resume
)

fail() {
  echo "agentsview-cli-contract check failed: $*" >&2
  exit 1
}

command -v agentsview >/dev/null 2>&1 \
  || fail "agentsview is not on PATH; run 'mise run test-agentsview-contract'"

for src in "${SOURCES[@]}"; do
  [ -f "$src" ] || fail "source file $src is missing"
done

# --- extract candidate command strings ------------------------------------
#
# One command per output line, prefixed with "<origin>\t": inline code spans
# are unwrapped, fenced code blocks are emitted verbatim, and backslash
# continuations are joined first.
extract_commands() {
  awk -v origin="$2" '
    # join backslash-continued lines
    {
      line = $0
      while (line ~ /\\$/ && (getline nextline) > 0) {
        sub(/[[:space:]]*\\$/, " ", line)
        sub(/^[[:space:]]+/, "", nextline)
        line = line nextline
      }
    }
    /^[[:space:]]*```/ { fenced = !fenced; next }
    fenced { print origin "\t" line; next }
    {
      # emit each inline code span on its own line
      rest = line
      while (match(rest, /`[^`]+`/)) {
        span = substr(rest, RSTART + 1, RLENGTH - 2)
        print origin "\t" span
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# --- help lookup with memoisation -----------------------------------------
HELP_DIR="$(mktemp -d)"
trap 'rm -rf "$HELP_DIR"' EXIT

# Prints the path of the cached help text, never the text itself: piping it
# into `grep -q` would SIGPIPE the writer and trip `set -o pipefail`.
help_file_for() {
  local subpath="$1"
  local cache="$HELP_DIR/${subpath// /_}.txt"

  if [ ! -f "$cache" ]; then
    local -a argv
    read -ra argv <<< "$subpath"
    agentsview "${argv[@]}" --help >"$cache" 2>&1 || true
  fi
  printf '%s\n' "$cache"
}

assert_subcommand() {
  local subpath="$1" origin="$2"
  grep -qE "^[[:space:]]+agentsview ${subpath}([[:space:]]|$)" "$(help_file_for "$subpath")" \
    || fail "subcommand 'agentsview ${subpath}' (cited in ${origin}) is not in the CLI's help"
}

assert_flag() {
  local subpath="$1" flag="$2" origin="$3"
  if [ "$flag" = "--help" ]; then
    return 0
  fi
  grep -qE "^[[:space:]]+(-[a-zA-Z], +)?${flag}([[:space:]]|$)" "$(help_file_for "$subpath")" \
    || fail "flag '${flag}' of 'agentsview ${subpath}' (cited in ${origin}) is not in the CLI's help"
}

# --- walk every cited command ---------------------------------------------
assertions=0
seen_flags=()

while IFS=$'\t' read -r origin cmd; do
  read -ra tokens <<< "$cmd"
  [ "${#tokens[@]}" -ge 2 ] || continue
  [ "${tokens[0]}" = "agentsview" ] || continue

  subpath=""
  i=1
  while [ "$i" -lt "${#tokens[@]}" ]; do
    tok="${tokens[$i]}"
    [[ "$tok" =~ ^[a-z][a-z0-9-]*$ ]] || break
    subpath="${subpath:+$subpath }$tok"
    i=$((i + 1))
  done
  [ -n "$subpath" ] || continue

  assert_subcommand "$subpath" "$origin"
  assertions=$((assertions + 1))

  while [ "$i" -lt "${#tokens[@]}" ]; do
    tok="${tokens[$i]}"
    if [[ "$tok" =~ ^--[a-z][a-z0-9-]*$ ]]; then
      assert_flag "$subpath" "$tok" "$origin"
      seen_flags+=("$tok")
      assertions=$((assertions + 1))
    fi
    i=$((i + 1))
  done
done < <(
  for src in "${SOURCES[@]}"; do
    extract_commands "$src" "${src#"$ROOT_DIR"/}"
  done
)

[ "$assertions" -gt 0 ] || fail "no 'agentsview ...' commands found in the skill files; the parser is broken"

# --- prose-only flags ------------------------------------------------------
for entry in "${PROSE_FLAGS[@]}"; do
  subpath="${entry%%:*}"
  flag="${entry##*:}"
  assert_subcommand "$subpath" "PROSE_FLAGS"
  assert_flag "$subpath" "$flag" "PROSE_FLAGS"
  seen_flags+=("$flag")
  assertions=$((assertions + 1))
done

# Every long flag in the skills must be accounted for, so a newly written
# prose flag cannot slip past unchecked.
declare -A accounted=()
for flag in "${seen_flags[@]}" "${FOREIGN_FLAGS[@]}" --help; do
  accounted["$flag"]=1
done

while IFS= read -r flag; do
  [ -n "${accounted[$flag]:-}" ] \
    || fail "flag '${flag}' is cited by a skill but checked by nothing; add it to PROSE_FLAGS (with its subcommand) or to FOREIGN_FLAGS"
done < <(grep -ohE -- '--[a-z][a-z0-9-]*' "${SOURCES[@]}" | sort -u)

echo "agentsview-cli-contract checks passed ($assertions assertions, $(agentsview --version))"
