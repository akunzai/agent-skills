#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"

fail() { echo "windows-path-guard check failed: $*" >&2; exit 1; }

extract_guard() {
  sed -n '/# >>> posix-path-guard >>>/,/# <<< posix-path-guard <<</p' "$1"
}

# Discover every script that carries the guard block (skills + plugins if present).
search_dirs=("$ROOT_DIR/skills")
[ -d "$ROOT_DIR/plugins" ] && search_dirs+=("$ROOT_DIR/plugins")
mapfile -t SCRIPTS < <(grep -rlF '# >>> posix-path-guard >>>' "${search_dirs[@]}" 2>/dev/null | sort)
[ "${#SCRIPTS[@]}" -ge 1 ] || fail "no script carries the posix-path-guard block"

# --- 1. All guard blocks are byte-identical ---
ref="$(extract_guard "${SCRIPTS[0]}")"
[ -n "$ref" ] || fail "empty guard block in ${SCRIPTS[0]}"
for s in "${SCRIPTS[@]}"; do
  [ "$(extract_guard "$s")" = "$ref" ] || fail "guard differs in $s vs ${SCRIPTS[0]}"
done

# --- 2. Guard prepends the MSYS bin, beating an injected fake tool ---
fake="$(mktemp -d)"
trap 'rm -rf "${fake:-}"' EXIT
cat > "$fake/find" <<'EOF'
#!/usr/bin/env bash
echo FAKE-FIND
EOF
chmod +x "$fake/find"

for os in msys cygwin; do
  resolved="$(PATH="$fake:$PATH" OSTYPE="$os" "$BASH_BIN" -c "$ref"$'\n''command -v find')"
  case "$resolved" in
    "$fake/find") fail "guard did not override the shadowing find for OSTYPE=$os (got $resolved)";;
  esac
  out="$(PATH="$fake:$PATH" OSTYPE="$os" "$BASH_BIN" -c "$ref"$'\n''find --version 2>/dev/null | head -n1')"
  case "$out" in
    *FAKE-FIND*) fail "guard let the fake find run for OSTYPE=$os";;
  esac
done

# --- 3. Missing tools => named error and non-zero exit (use a guard-bearing script with tool checks) ---
# Prefer mem-sync-git.sh since it has tool checks; plugin loaders may exit early.
probe=
for s in "${SCRIPTS[@]}"; do
  if [[ "$s" == *"mem-sync-git.sh"* ]]; then
    probe="$s"
    break
  fi
done
[ -n "$probe" ] || probe="${SCRIPTS[0]}"
set +e
err="$(PATH="/nonexistent-dir" OSTYPE="linux-gnu" "$BASH_BIN" "$probe" print-branch 2>&1)"
code=$?
set -e
[ "$code" -ne 0 ] || fail "missing-tools run should exit non-zero"
case "$err" in
  *"required POSIX tool"*) ;;
  *) fail "missing-tools error should name the requirement; got: $err";;
esac

echo "windows-path-guard tests passed"
