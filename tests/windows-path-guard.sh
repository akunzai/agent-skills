#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT_DIR/skills/mem-sync/scripts/mem-sync-git.sh"
LOADER="$ROOT_DIR/plugins/memory-autoload/hooks/load-memory.sh"
BASH_BIN="$(command -v bash)"

fail() { echo "windows-path-guard check failed: $*" >&2; exit 1; }

extract_guard() {
  sed -n '/# >>> posix-path-guard >>>/,/# <<< posix-path-guard <<</p' "$1"
}

# --- 1. Guard blocks are byte-identical ---
g_sync="$(extract_guard "$SYNC")"
g_load="$(extract_guard "$LOADER")"
[ -n "$g_sync" ] || fail "guard block missing in mem-sync-git.sh"
[ "$g_sync" = "$g_load" ] || fail "guard differs between mem-sync-git.sh and load-memory.sh"

# --- 2. Guard prepends the MSYS bin, beating an injected fake tool ---
# Put a fake `find` early on PATH; under OSTYPE=msys the guard prepends
# /usr/bin so the real /usr/bin/find wins (on Linux CI /usr/bin/find is real).
fake="$(mktemp -d)"
trap 'rm -rf "${fake:-}"' EXIT
cat > "$fake/find" <<'EOF'
#!/usr/bin/env bash
echo FAKE-FIND
EOF
chmod +x "$fake/find"

for os in msys cygwin; do
  resolved="$(PATH="$fake:$PATH" OSTYPE="$os" "$BASH_BIN" -c "$g_sync"$'\n''command -v find')"
  case "$resolved" in
    "$fake/find") fail "guard did not override the shadowing find for OSTYPE=$os (got $resolved)";;
  esac
  out="$(PATH="$fake:$PATH" OSTYPE="$os" "$BASH_BIN" -c "$g_sync"$'\n''find --version 2>/dev/null | head -n1')"
  case "$out" in
    *FAKE-FIND*) fail "guard let the fake find run for OSTYPE=$os";;
  esac
done

# --- 3. Missing tools => named error and non-zero exit ---
set +e
err="$(PATH="/nonexistent-dir" OSTYPE="linux-gnu" "$BASH_BIN" "$SYNC" print-branch 2>&1)"
code=$?
set -e
[ "$code" -ne 0 ] || fail "missing-tools run should exit non-zero"
case "$err" in
  *"required POSIX tool"*) ;;
  *) fail "missing-tools error should name the requirement; got: $err";;
esac

echo "windows-path-guard tests passed"
