#!/usr/bin/env bash
set -euo pipefail

# Compares the facts recorded in docs/agents/verification.md against the
# repository as it stands now. Reports drift; never fixes it.
#
# Facts are carried by HTML-comment markers in that file, so they stay
# invisible when rendered and unambiguous to parse:
#
#   <!-- drift:forge github -->
#   <!-- drift:entrypoint scripts/dev-up.sh -->
#   <!-- drift:port 8080 -->
#   <!-- drift:file .devcontainer/mock/mappings/tenant.json -->
#
# A value still wrapped in <angle brackets> is an unfilled template
# placeholder, and is reported as drift in its own right.
#
# Adding a marker kind touches five places: the marker list above, its
# check below, references/templates/verification.md, the Re-running
# section of SKILL.md, and tests/setup-agent-ready-repo-drift.sh.

usage() {
  cat >&2 <<'USAGE'
usage: check-drift.sh [--run-entrypoint] [DIR]

  --run-entrypoint  also execute the recorded entrypoint and require exit 0
  DIR               repository root (default: current directory)
USAGE
}

RUN_ENTRYPOINT=false
DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-entrypoint) RUN_ENTRYPOINT=true ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [ -n "$DIR" ]; then
        echo "unexpected argument: $1" >&2
        usage
        exit 2
      fi
      DIR="$1"
      ;;
  esac
  shift
done

DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 2; }
DIR="$(cd "$DIR" && pwd)"

DOC="$DIR/docs/agents/verification.md"
if [ ! -f "$DOC" ]; then
  echo "no docs/agents/verification.md in $DIR; nothing recorded to check" >&2
  exit 2
fi

DRIFT=0

report_ok() { printf 'ok    %s\n' "$*"; }
report_drift() { printf 'DRIFT %s\n' "$*"; DRIFT=1; }
report_skip() { printf 'skip  %s\n' "$*"; }

markers() {
  grep -oE "<!--[[:space:]]*drift:$1[[:space:]]+[^[:space:]]+[[:space:]]*-->" "$DOC" \
    | sed -E "s|<!--[[:space:]]*drift:$1[[:space:]]+||; s|[[:space:]]*-->||" || true
}

# An unedited template still carries <angle> placeholders. That is a
# document nobody finished, which is exactly what this script is for.
unfilled() {
  case "$1" in
    \<*\>) return 0 ;;
    *) return 1 ;;
  esac
}

# A marker path is repo-relative by construction; anything else is a
# malformed document rather than a fact about the repo.
safe_path() {
  case "$1" in
    /*|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

# --- forge: ask the host's API first, fall back to the domain ---
remote_forge() {
  local url
  url="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || { echo "none"; return; }
  if (cd "$DIR" && gh repo view --json name) >/dev/null 2>&1; then
    echo "github"
    return
  fi
  if (cd "$DIR" && glab api version) >/dev/null 2>&1; then
    echo "gitlab"
    return
  fi
  case "$url" in
    *github.com*) echo "github" ;;
    *gitlab.com*) echo "gitlab" ;;
    *) echo "unknown" ;;
  esac
}

FORGE_MARKERS="$(markers forge)"
FORGE_COUNT="$(markers forge | grep -c . || true)"

if [ "$FORGE_COUNT" -gt 1 ]; then
  report_drift "forge: $FORGE_COUNT drift:forge markers; a repo has one origin"
elif [ "$FORGE_COUNT" -eq 1 ]; then
  documented="$FORGE_MARKERS"
  if unfilled "$documented"; then
    report_drift "forge: '$documented' is an unfilled template placeholder"
  else
    actual="$(remote_forge)"
    case "$actual" in
      unknown)
        report_skip "forge: neither gh nor glab could identify the host"
        ;;
      none)
        if [ "$documented" = "none" ]; then
          report_ok "forge: no remote, as documented"
        else
          report_drift "forge: documented '$documented' but the repo has no origin remote"
        fi
        ;;
      *)
        if [ "$documented" = "$actual" ]; then
          report_ok "forge: $actual"
        else
          report_drift "forge: documented '$documented' but origin resolves to '$actual'"
        fi
        ;;
    esac
  fi
fi

# --- entrypoint ---
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if unfilled "$path"; then
    report_drift "entrypoint: '$path' is an unfilled template placeholder"
    continue
  fi
  if ! safe_path "$path"; then
    report_drift "entrypoint: '$path' is not a repo-relative path"
    continue
  fi
  if [ ! -f "$DIR/$path" ]; then
    report_drift "entrypoint: $path no longer exists"
    continue
  fi
  if [ ! -x "$DIR/$path" ]; then
    report_drift "entrypoint: $path is not executable"
    continue
  fi
  if [ "$RUN_ENTRYPOINT" = true ]; then
    # Drive it through the environment rather than a flag, so any
    # entrypoint honouring the documented detection order qualifies.
    if (cd "$DIR" && NON_INTERACTIVE=true CI=true "./$path") >/dev/null 2>&1; then
      report_ok "entrypoint: $path ran clean"
    else
      report_drift "entrypoint: $path exited non-zero"
    fi
  else
    report_ok "entrypoint: $path present and executable"
  fi
done < <(markers entrypoint)

# --- ports, against a compose file when there is one ---
COMPOSE=""
for candidate in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
  if [ -f "$DIR/$candidate" ]; then
    COMPOSE="$DIR/$candidate"
    break
  fi
done

while IFS= read -r port; do
  [ -n "$port" ] || continue
  if unfilled "$port"; then
    report_drift "port: '$port' is an unfilled template placeholder"
  elif ! printf '%s' "$port" | grep -qE '^[0-9]+$'; then
    report_drift "port: '$port' is not a number"
  elif [ -z "$COMPOSE" ]; then
    report_skip "port $port: no compose file to compare against"
  elif grep -qE "(^|[^0-9])$port([^0-9]|$)" "$COMPOSE"; then
    report_ok "port $port: present in $(basename "$COMPOSE")"
  else
    report_drift "port $port: documented but absent from $(basename "$COMPOSE")"
  fi
done < <(markers port)

# --- files the documentation depends on, mock scenarios included ---
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if unfilled "$path"; then
    report_drift "file: '$path' is an unfilled template placeholder"
  elif ! safe_path "$path"; then
    report_drift "file: '$path' is not a repo-relative path"
  elif [ -e "$DIR/$path" ]; then
    report_ok "file: $path"
  else
    report_drift "file: $path no longer exists"
  fi
done < <(markers file)

if [ "$DRIFT" -ne 0 ]; then
  echo "Drift found. Report it; do not fix it without confirmation."
  exit 1
fi

echo "No drift found."
