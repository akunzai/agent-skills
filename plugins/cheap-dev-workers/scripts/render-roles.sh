#!/usr/bin/env bash
set -euo pipefail

# Projects the canonical Worker Role sources in roles/ onto the two native
# artifact sets the runtimes actually load. See ../AGENTS.md for ownership and
# docs/adr/0001-canonical-worker-role-source.md for the trade-off.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLES_DIR="$PLUGIN_ROOT/roles"
SHARED="$ROLES_DIR/shared.role"
MD_DIR="$PLUGIN_ROOT/agents"
TOML_DIR="$PLUGIN_ROOT/codex-agents"
ROLES=(check-runner commit-writer log-summarizer repo-explorer)

usage() {
  cat <<'EOF'
Usage: render-roles.sh --check | --write

Project roles/*.role onto agents/*.md and codex-agents/*.toml.

  --check     Render into a temporary directory and compare with the committed
              artifacts. Writes nothing. Exit 1 when they differ.
  --write     Validate every role, then replace all eight artifacts. Any
              failure leaves every artifact untouched.
  -h, --help  Show this help

Exit codes: 0 ok, 1 drift detected, 64 usage error, 65 invalid source.
EOF
}

mode=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check | --write)
      if [[ -n "$mode" ]]; then
        echo "Choose either --check or --write, not both" >&2
        exit 64
      fi
      mode="${1#--}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$mode" ]]; then
  echo "Missing --check or --write" >&2
  usage >&2
  exit 64
fi

if [[ ! -f "$SHARED" ]]; then
  echo "$SHARED: missing shared Worker Role skeleton" >&2
  exit 65
fi

# --- the source role set must equal the fixed role set, exactly ---
declared="$(printf '%s\n' "${ROLES[@]}" | sort)"
on_disk="$(
  find "$ROLES_DIR" -maxdepth 1 -name '*.role' ! -name 'shared.role' \
    -exec basename {} .role \; | sort
)"
if [[ "$declared" != "$on_disk" ]]; then
  echo "$ROLES_DIR: role sources do not match the fixed role set" >&2
  echo "  expected: $(echo "$declared" | tr '\n' ' ')" >&2
  echo "  found:    $(echo "$on_disk" | tr '\n' ' ')" >&2
  exit 65
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/render-roles.XXXXXX")"
trap 'rm -rf "$work"' EXIT

for role in "${ROLES[@]}"; do
  awk -v sharedfile="$SHARED" -v role="$role" \
    -v outmd="$work/$role.md" -v outtoml="$work/$role.toml" \
    -v outuses="$work/$role.uses" \
    -f "$PLUGIN_ROOT/scripts/render-roles.awk" \
    "$SHARED" "$ROLES_DIR/$role.role"
done

# --- every shared id must be applied by exactly the roles that reference it ---
awk -v sharedfile="$SHARED" -v work="$work" -v roles="${ROLES[*]}" \
  -f "$PLUGIN_ROOT/scripts/render-roles-applies.awk" </dev/null

status=0
case "$mode" in
  check)
    for role in "${ROLES[@]}"; do
      if ! cmp -s "$work/$role.md" "$MD_DIR/$role.md"; then
        echo "drift: agents/$role.md differs from roles/$role.role" >&2
        status=1
      fi
      if ! cmp -s "$work/$role.toml" "$TOML_DIR/$role.toml"; then
        echo "drift: codex-agents/$role.toml differs from roles/$role.role" >&2
        status=1
      fi
    done
    if [[ $status -eq 0 ]]; then
      echo "render-roles: all eight artifacts match roles/"
    fi
    ;;
  write)
    # Everything above validated; only now does anything move into place.
    for role in "${ROLES[@]}"; do
      for pair in "$MD_DIR/$role.md:$work/$role.md" \
        "$TOML_DIR/$role.toml:$work/$role.toml"; do
        target="${pair%%:*}"
        rendered="${pair#*:}"
        temporary="$(mktemp "$(dirname "$target")/.render.XXXXXX")"
        cat "$rendered" > "$temporary"
        chmod 644 "$temporary"
        mv "$temporary" "$target"
      done
    done
    echo "render-roles: wrote 8 artifacts from roles/"
    ;;
esac

exit "$status"
