#!/usr/bin/env bash
set -euo pipefail

# Bumps this repo's exact ("not latest") tool pins the way Dependabot would,
# if Dependabot could see mise-managed pins (it cannot yet -- see
# dependabot-core#12320). One tool per invocation: `--list` reports current
# vs. latest for every pin, `--apply <tool>` rewrites every file that pins
# that tool to its latest stable release.
#
# Release lookup is injectable so tests/bump-pinned-tools.sh can run offline:
#   BUMP_TOOLS_RELEASES_CMD  overrides the "list stable release tags for a
#                            repo" step. Called as `$CMD <owner/repo>`,
#                            must print one tag per line.
#   BUMP_TOOLS_SHA_CMD       overrides the "resolve a tag to a commit sha"
#                            step (only skillspector needs this). Called as
#                            `$CMD <owner/repo> <tag>`, must print the sha.
# Both default to `gh api`. Neither is read unless set -- an unset override
# falls through to the default, so a partial stub (only one of the two) is
# safe.
#
# bash 3.2 compatible (macOS ships that as /bin/bash): no associative
# arrays, no `mapfile`.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISE_TOML="$ROOT_DIR/mise.toml"
WAZA_EVAL_YML="$ROOT_DIR/.github/workflows/waza-eval.yml"
AGENTSVIEW_EXTRACT_SKILL="$ROOT_DIR/skills/agentsview-extract/SKILL.md"
AGENTSVIEW_RESUME_SKILL="$ROOT_DIR/skills/agentsview-resume/SKILL.md"

# Fixed processing order for --list; --apply takes any one of these names.
TOOL_ORDER=(zizmor gitleaks waza agentsview skillspector)

usage() {
  cat <<'EOF'
Usage: bump-pinned-tools.sh --list
       bump-pinned-tools.sh --apply <tool>

  --list          Print current vs. latest stable release per pinned tool.
  --apply <tool>  Rewrite every file that pins <tool> to its latest stable
                  release. Idempotent: a tool already at latest, or a tool
                  not pinned in mise.toml (e.g. gitleaks before its own
                  slice lands), is reported as an untouched no-op.
  -h, --help      Show this help

Tools: zizmor gitleaks waza agentsview skillspector
EOF
}

# --- GitHub repo each pin tracks --------------------------------------------
#
# Plain `[tools]` exact pins (mise.toml `name = "X.Y.Z"`, GitHub tag
# `vX.Y.Z`) are the `zizmor|gitleaks` arm below: adding a new one is one
# line here plus one line in TOOL_ORDER above -- current_simple/apply_simple
# already handle any name routed through them. waza, agentsview, and
# skillspector are special-cased because each pins the same version across
# more than one file, in more than one on-disk format.
repo_for() {
  case "$1" in
    zizmor) echo "zizmorcore/zizmor" ;;
    gitleaks) echo "gitleaks/gitleaks" ;;
    waza) echo "microsoft/waza" ;;
    agentsview) echo "kenn-io/agentsview" ;;
    skillspector) echo "NVIDIA/SkillSpector" ;;
    *) return 1 ;;
  esac
}

# --- release lookup ----------------------------------------------------------

fetch_releases() {
  local repo="$1"
  if [ -n "${BUMP_TOOLS_RELEASES_CMD:-}" ]; then
    $BUMP_TOOLS_RELEASES_CMD "$repo"
    return
  fi
  gh api "repos/${repo}/releases" --paginate --jq \
    '.[] | select(.draft == false and .prerelease == false) | .tag_name'
}

fetch_commit_sha() {
  local repo="$1" tag="$2"
  if [ -n "${BUMP_TOOLS_SHA_CMD:-}" ]; then
    $BUMP_TOOLS_SHA_CMD "$repo" "$tag"
    return
  fi
  gh api "repos/${repo}/commits/${tag}" --jq '.sha'
}

# Highest stable `vX.Y.Z` tag for a repo, printed without the `v`. Every pin
# here tags stable releases as `vX.Y.Z`; some repos (microsoft/waza) also
# publish unrelated tags (an azd extension release) that must not be picked
# up as "latest" -- the exact match below excludes them.
latest_stable_version() {
  local repo="$1" result
  result="$(fetch_releases "$repo" \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed -E 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1)" || true
  printf '%s' "$result"
}

# --- current version per tool ------------------------------------------------

current_simple() {
  local name="$1" result
  result="$(sed -nE "s/^${name} = \"([0-9]+\.[0-9]+\.[0-9]+)\"\$/\1/p" "$MISE_TOML" | head -1)"
  printf '%s' "$result"
}

current_waza() {
  local result
  # Only one top-level `version = "X.Y.Z"` line exists in mise.toml today,
  # inside the microsoft/waza tool block; a second one anywhere else would
  # need this scoped to that block.
  result="$(sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$MISE_TOML" | head -1)"
  printf '%s' "$result"
}

current_agentsview() {
  local result
  result="$(sed -nE 's/.*"github:kenn-io\/agentsview" = "v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$MISE_TOML" | head -1)"
  printf '%s' "$result"
}

current_skillspector_version() {
  local result
  result="$(sed -nE 's/^SKILLSPECTOR_REF="[0-9a-f]+" # v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' "$MISE_TOML" | head -1)"
  printf '%s' "$result"
}

current_version_for() {
  local name="$1"
  case "$name" in
    zizmor | gitleaks) current_simple "$name" ;;
    waza) current_waza ;;
    agentsview) current_agentsview ;;
    skillspector) current_skillspector_version ;;
  esac
}

# --- rewrite per tool ---------------------------------------------------------

apply_simple() {
  local name="$1" new="$2"
  sed -i.bak -E "s/^(${name}) = \"[0-9]+\.[0-9]+\.[0-9]+\"\$/\1 = \"${new}\"/" "$MISE_TOML"
  rm -f "${MISE_TOML}.bak"
}

apply_waza() {
  local new="$1"
  sed -i.bak -E "s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"\$/version = \"${new}\"/" "$MISE_TOML"
  rm -f "${MISE_TOML}.bak"
  sed -i.bak -E "s/(install_args: github:microsoft\/waza@)[0-9]+\.[0-9]+\.[0-9]+/\1${new}/" "$WAZA_EVAL_YML"
  rm -f "${WAZA_EVAL_YML}.bak"
}

apply_agentsview() {
  local new="$1"
  sed -i.bak -E "s/(\"github:kenn-io\/agentsview\" = \")v[0-9]+\.[0-9]+\.[0-9]+(\")/\1v${new}\2/" "$MISE_TOML"
  rm -f "${MISE_TOML}.bak"
  local f
  for f in "$AGENTSVIEW_EXTRACT_SKILL" "$AGENTSVIEW_RESUME_SKILL"; do
    sed -i.bak -E \
      -e "s/agentsview==[0-9]+\.[0-9]+\.[0-9]+/agentsview==${new}/" \
      -e "s/agentsview@v[0-9]+\.[0-9]+\.[0-9]+/agentsview@v${new}/" \
      "$f"
    rm -f "${f}.bak"
  done
}

apply_skillspector() {
  local new_version="$1" new_sha="$2"
  sed -i.bak -E "s/^SKILLSPECTOR_REF=\"[0-9a-f]+\" # v[0-9]+\.[0-9]+\.[0-9]+\$/SKILLSPECTOR_REF=\"${new_sha}\" # v${new_version}/" "$MISE_TOML"
  rm -f "${MISE_TOML}.bak"
}

# --- commands -----------------------------------------------------------------

do_list() {
  printf 'tool\tcurrent\tlatest\tstatus\n'
  local name repo old new status
  for name in "${TOOL_ORDER[@]}"; do
    repo="$(repo_for "$name")"
    old="$(current_version_for "$name")"
    new="$(latest_stable_version "$repo")"
    if [ -z "$old" ]; then
      status="unpinned"
      old="-"
    elif [ "$old" = "$new" ]; then
      status="up-to-date"
    else
      status="behind"
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$old" "${new:--}" "$status"
  done
}

do_apply() {
  local name="$1" repo old new sha
  repo="$(repo_for "$name")" || {
    echo "bump-pinned-tools: unknown tool '$name'" >&2
    exit 64
  }

  old="$(current_version_for "$name")"

  if [ -z "$old" ]; then
    echo "tool=$name"
    echo "old_version="
    echo "changed=false"
    echo "note=not pinned in mise.toml, nothing to do"
    return 0
  fi

  new="$(latest_stable_version "$repo")"
  if [ -z "$new" ]; then
    echo "bump-pinned-tools: could not resolve a latest stable release for $name ($repo)" >&2
    exit 1
  fi

  if [ "$old" = "$new" ]; then
    echo "tool=$name"
    echo "old_version=$old"
    echo "new_version=$new"
    echo "changed=false"
    return 0
  fi

  case "$name" in
    zizmor | gitleaks) apply_simple "$name" "$new" ;;
    waza) apply_waza "$new" ;;
    agentsview) apply_agentsview "$new" ;;
    skillspector)
      sha="$(fetch_commit_sha "$repo" "v${new}")"
      if [ -z "$sha" ]; then
        echo "bump-pinned-tools: could not resolve a commit sha for ${repo}@v${new}" >&2
        exit 1
      fi
      apply_skillspector "$new" "$sha"
      ;;
  esac

  echo "tool=$name"
  echo "old_version=$old"
  echo "new_version=$new"
  echo "changed=true"
  echo "release_url=https://github.com/${repo}/releases/tag/v${new}"
  if [ "$name" = "skillspector" ]; then
    echo "commit_sha=$sha"
  fi
  return 0
}

# --- entrypoint -----------------------------------------------------------

case "${1:-}" in
  --list)
    do_list
    ;;
  --apply)
    if [ $# -lt 2 ] || [ -z "$2" ]; then
      usage >&2
      exit 64
    fi
    do_apply "$2"
    ;;
  -h | --help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
