#!/usr/bin/env bash
# mem-setup-bridge — wire each installed coding agent's global memory file to a
# single canonical AGENTS.md.  `plan` is read-only; `apply` mutates with backups.
set -euo pipefail

# >>> posix-path-guard >>>
# On Windows (Git Bash / MSYS / Cygwin), make MSYS coreutils win over the
# native find.exe/tar.exe in C:\Windows\System32. Keep this block identical
# across scripts (verified by tests/windows-path-guard.sh).
case "${OSTYPE:-}" in
  msys*|cygwin*)
    if [ -x /usr/bin/sed ]; then
      PATH="/usr/bin:/bin:$PATH"
    elif command -v git >/dev/null 2>&1; then
      _git_root="$(dirname "$(dirname "$(command -v git)")")"
      [ -x "$_git_root/usr/bin/sed" ] && PATH="$_git_root/usr/bin:$_git_root/bin:$PATH"
      unset _git_root
    fi
    ;;
esac
# <<< posix-path-guard <<<

_msg_missing=""
for _tool in sed grep ln mv cp mktemp date readlink dirname; do
  command -v "$_tool" >/dev/null 2>&1 || _msg_missing="$_msg_missing $_tool"
done
if [ -n "$_msg_missing" ]; then
  echo "Error: required POSIX tool(s) not found:$_msg_missing" >&2
  echo "On Windows, run mem-setup through Git Bash so its usr/bin tools are on PATH." >&2
  exit 1
fi
unset _msg_missing _tool

CANONICAL="${MEM_SETUP_CANONICAL:-$HOME/.agents/AGENTS.md}"
# Optional augmentation modules (colon-separated absolute paths) for low-tier
# agents. Empty by default — the product ships no content.
AUGMENT="${MEM_SETUP_AUGMENT:-}"

# Registry: name|detect_dir|tier|method|target
REGISTRY="\
claude|$HOME/.claude|high|import|$HOME/.claude/CLAUDE.md
codex|$HOME/.codex|high|symlink|$HOME/.codex/AGENTS.md
pi|$HOME/.pi/agent|high|symlink|$HOME/.pi/agent/AGENTS.md
gemini|$HOME/.gemini|low|import|$HOME/.gemini/GEMINI.md
opencode|$HOME/.config/opencode|low|config|$HOME/.config/opencode/opencode.json"

is_windows_shell() { case "${OSTYPE:-}" in msys*|cygwin*) return 0;; *) return 1;; esac; }

# Print the source files a tier should reference: core, plus augment for low tier.
sources_for_tier() {
  local tier="$1"
  printf '%s\n' "$CANONICAL"
  if [ "$tier" = low ] && [ -n "$AUGMENT" ]; then
    printf '%s\n' "$AUGMENT" | tr ':' '\n' | grep -v '^$' || true
  fi
}

classify() {
  if [ -L "$1" ]; then echo symlink
  elif [ -e "$1" ]; then echo file
  else echo missing
  fi
}

backup_file() {
  local f="$1" ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$f" "$f.bak-$ts"
  echo "    backed up: $f -> $f.bak-$ts"
}

plan_one() {
  local name="$1" tier="$2" method="$3" target="$4" state src
  state="$(classify "$target")"
  echo "  [$name] tier=$tier method=$method"
  echo "    target: $target ($state)"
  case "$method" in
    import|config)
      while IFS= read -r src; do echo "    reference: $src"; done < <(sources_for_tier "$tier") ;;
    symlink)
      if is_windows_shell; then
        echo "    reference: $CANONICAL (Windows: copy, no symlink)"
      else
        echo "    reference: $CANONICAL (symlink)"
      fi ;;
  esac
  case "$state" in
    file)    echo "    on apply: back up real file, then update in place";;
    symlink) echo "    on apply: remove existing symlink (target content untouched), then recreate";;
    missing) echo "    on apply: create new";;
  esac
}

apply_import() {
  local target="$1" tier="$2" state src changed=0
  mkdir -p "$(dirname "$target")"
  state="$(classify "$target")"
  if [ "$state" = symlink ]; then rm "$target"; state=missing; fi
  if [ "$state" = missing ]; then
    {
      echo "# Global instructions — single source of truth is the canonical AGENTS.md."
      while IFS= read -r src; do echo "@$src"; done < <(sources_for_tier "$tier")
    } > "$target"
    echo "    wrote import stub: $target"
    return
  fi
  while IFS= read -r src; do
    grep -qF "@$src" "$target" || changed=1
  done < <(sources_for_tier "$tier")
  if [ "$changed" -eq 0 ]; then echo "    already bridged: $target"; return; fi
  backup_file "$target"
  while IFS= read -r src; do
    grep -qF "@$src" "$target" || printf '@%s\n' "$src" >> "$target"
  done < <(sources_for_tier "$tier")
  echo "    appended @import line(s): $target"
}

apply_symlink() {
  local target="$1" state
  mkdir -p "$(dirname "$target")"
  state="$(classify "$target")"
  if is_windows_shell; then
    # Never cp through a symlink (would clobber its target); remove it first.
    if [ "$state" = symlink ]; then
      rm "$target"
    elif [ "$state" = file ]; then
      backup_file "$target"
    fi
    cp "$CANONICAL" "$target"
    echo "    copied (Windows): $CANONICAL -> $target (re-run to refresh)"
    return
  fi
  if [ "$state" = symlink ]; then
    if [ "$(readlink "$target")" = "$CANONICAL" ]; then echo "    already linked: $target"; return; fi
    rm "$target"
  elif [ "$state" = file ]; then
    backup_file "$target"; rm "$target"
  fi
  ln -s "$CANONICAL" "$target"
  echo "    linked: $target -> $CANONICAL"
}

apply_config() {
  local target="$1" tier="$2"
  mkdir -p "$(dirname "$target")"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "    python3 not found; add these to \"instructions\" in $target manually:"
    sources_for_tier "$tier" | sed 's/^/      - /'
    return
  fi
  python3 - "$target" "$tier" "$CANONICAL" "$AUGMENT" <<'PY'
import json, os, shutil, sys, time
target, tier, canonical, augment = sys.argv[1:5]
paths = [canonical]
if tier == "low" and augment:
    paths += [p for p in augment.split(":") if p]
existed = os.path.exists(target)
try:
    with open(target) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except FileNotFoundError:
    data = {}
except json.JSONDecodeError:
    sys.stderr.write("    skipped: %s is not valid JSON; fix it and re-run\n" % target)
    sys.exit(0)
ins = data.get("instructions")
if not isinstance(ins, list):
    ins = []
changed = False
for p in paths:
    if p not in ins:
        ins.append(p)
        changed = True
data["instructions"] = ins
if changed:
    if existed:
        shutil.copy(target, "%s.bak-%s" % (target, time.strftime("%Y%m%d-%H%M%S")))
    with open(target, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("    updated instructions[]:", target)
else:
    print("    already in instructions[]:", target)
PY
}

run() {
  local action="$1" name dir tier method target
  while IFS='|' read -r name dir tier method target; do
    [ -n "$name" ] || continue
    [ -d "$dir" ] || continue
    case "$action" in
      plan) plan_one "$name" "$tier" "$method" "$target" ;;
      apply)
        echo "  [$name] tier=$tier method=$method"
        case "$method" in
          import)  apply_import  "$target" "$tier" ;;
          symlink) apply_symlink "$target" ;;
          config)  apply_config  "$target" "$tier" ;;
        esac ;;
    esac
  done <<EOF
$REGISTRY
EOF
}

require_canonical() {
  if [ ! -e "$CANONICAL" ]; then
    echo "Error: canonical memory file not found: $CANONICAL" >&2
    echo "Create it first (your durable cross-agent instructions) or set MEM_SETUP_CANONICAL." >&2
    exit 1
  fi
}

case "${1:-plan}" in
  plan)
    require_canonical
    echo "mem-setup plan (canonical: $CANONICAL)"
    run plan ;;
  apply)
    require_canonical
    echo "mem-setup apply (canonical: $CANONICAL)"
    run apply ;;
  print-canonical) printf '%s\n' "$CANONICAL" ;;
  *)
    echo "Usage: $0 {plan|apply|print-canonical}" >&2
    exit 1 ;;
esac
