#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/mem-setup/scripts/mem-setup-bridge.sh"

fail() { echo "mem-setup-bridge check failed: $*" >&2; exit 1; }

HOME_DIR="$(mktemp -d)"
trap 'rm -rf "${HOME_DIR:-}"' EXIT

mkdir -p "$HOME_DIR/.agents"
printf 'CANONICAL-CORE\n' > "$HOME_DIR/.agents/AGENTS.md"
printf 'AUGMENT-MODULE\n' > "$HOME_DIR/.agents/AUGMENT.md"
CANON="$HOME_DIR/.agents/AGENTS.md"
AUG="$HOME_DIR/.agents/AUGMENT.md"

mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex" "$HOME_DIR/.pi/agent" \
         "$HOME_DIR/.gemini" "$HOME_DIR/.config/opencode"

run() {
  HOME="$HOME_DIR" MEM_SETUP_CANONICAL="$CANON" MEM_SETUP_AUGMENT="$AUG" \
    OSTYPE="linux-gnu" bash "$SCRIPT" "$@"
}

# --- plan is read-only ---
run plan >/dev/null
[ ! -e "$HOME_DIR/.claude/CLAUDE.md" ] || fail "plan created a file"
[ ! -e "$HOME_DIR/.codex/AGENTS.md" ] || fail "plan created a file"

# --- apply ---
run apply >/dev/null

# claude (high): import core only
grep -qF "@$CANON" "$HOME_DIR/.claude/CLAUDE.md" || fail "claude stub missing core import"
if grep -qF "@$AUG" "$HOME_DIR/.claude/CLAUDE.md"; then fail "claude (high) must not import augment"; fi

# gemini (low): import core + augment
grep -qF "@$CANON" "$HOME_DIR/.gemini/GEMINI.md" || fail "gemini stub missing core import"
grep -qF "@$AUG" "$HOME_DIR/.gemini/GEMINI.md" || fail "gemini (low) missing augment import"

# codex/pi: symlink to canonical core
[ -L "$HOME_DIR/.codex/AGENTS.md" ] || fail "codex must be a symlink"
[ "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$CANON" ] || fail "codex symlink wrong target"
[ -L "$HOME_DIR/.pi/agent/AGENTS.md" ] || fail "pi must be a symlink"

# opencode: instructions[] contains core + augment (python3 only)
if command -v python3 >/dev/null 2>&1; then
  python3 - "$HOME_DIR/.config/opencode/opencode.json" "$CANON" "$AUG" <<'PY' \
    || fail "opencode instructions[] wrong"
import json, sys
d = json.load(open(sys.argv[1]))
ins = d["instructions"]
assert sys.argv[2] in ins and sys.argv[3] in ins
PY
fi

# --- idempotency: second apply reports no changes for the import bridge ---
out="$(run apply)"
case "$out" in
  *"already bridged"*) ;;
  *) fail "second apply should report 'already bridged' for import targets";;
esac
# an idempotent re-run must not back up anything (covers all bridge methods)
if find "$HOME_DIR" -name '*.bak-*' | grep -q .; then fail "idempotent apply created backups"; fi

# --- regression: apply must NOT write through a symlink and clobber canonical ---
rm -f "$HOME_DIR/.claude/CLAUDE.md"
ln -s "$CANON" "$HOME_DIR/.claude/CLAUDE.md"
run apply >/dev/null
[ "$(cat "$CANON")" = "CANONICAL-CORE" ] || fail "apply wrote through symlink and clobbered canonical"
[ ! -L "$HOME_DIR/.claude/CLAUDE.md" ] || fail "apply should replace the symlink with a real stub"
grep -qF "@$CANON" "$HOME_DIR/.claude/CLAUDE.md" || fail "replacement stub missing import"

# --- only installed agents are touched ---
HOME_DIR2="$(mktemp -d)"
mkdir -p "$HOME_DIR2/.agents" "$HOME_DIR2/.codex"
printf 'CORE\n' > "$HOME_DIR2/.agents/AGENTS.md"
HOME="$HOME_DIR2" MEM_SETUP_CANONICAL="$HOME_DIR2/.agents/AGENTS.md" OSTYPE="linux-gnu" \
  bash "$SCRIPT" apply >/dev/null
[ -e "$HOME_DIR2/.codex/AGENTS.md" ] || fail "installed codex not bridged"
[ ! -e "$HOME_DIR2/.gemini/GEMINI.md" ] || fail "uninstalled gemini must be skipped"
rm -rf "$HOME_DIR2"

echo "mem-setup-bridge tests passed"
