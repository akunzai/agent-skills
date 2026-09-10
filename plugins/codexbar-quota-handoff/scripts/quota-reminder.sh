#!/usr/bin/env bash
# Quota-reminder hook shared by every consuming tool (Claude Code, Grok
# Build, Codex CLI, GitHub Copilot CLI), registered on both Stop and
# PostToolUse through each tool's native hook location. A no-op unless
# codexbar-quota-flag.sh has written a flag, for this tool's provider, since
# the last time this fired.
#
# Stop alone fires only once per turn — after the whole nested tool-call loop
# finishes — so a long, continuous stretch of tool calls within a single turn
# (a real risk during an implementation-heavy session) could burn through the
# quota well before Stop ever gets a chance to fire. PostToolUse fires after
# every individual tool call instead, closing that gap; it can't block the
# way Stop can (the tool has already run by the time it fires), but exit 2
# still surfaces its stderr to the model the same way, which is all this
# reminder ever needed — it was never meant to force a stop, just to relay a
# short message once the model reads it. Grok is Stop-only: its PostToolUse
# treats exit 2 as fail-open and would claim the flag before Stop can surface
# the reminder.
#
# Which tool is running is inferred from environment variables each hook
# runner sets natively — not the shared CLAUDE_PLUGIN_ROOT compatibility
# alias, which all four tools set and can't disambiguate anything:
#   - Grok Build sets GROK_SESSION_ID (its own hook-runner variable, per its
#     locally-installed user-guide docs, ~/.grok/docs/user-guide/10-hooks.md).
#   - GitHub Copilot CLI sets COPILOT_CLI=1 (observed by dumping the hook
#     environment under Copilot CLI 1.0.82; COPILOT_PROJECT_DIR comes with
#     it). This must be checked *before* PLUGIN_ROOT: Copilot supports both
#     the ${CLAUDE_PLUGIN_ROOT} and ${PLUGIN_ROOT} placeholders and exports a
#     bare PLUGIN_ROOT to plugin hooks too, so the Codex test alone would
#     misreport Copilot as Codex and claim the Codex flag.
#   - Codex CLI sets a bare PLUGIN_ROOT *in addition to* the CLAUDE_PLUGIN_ROOT
#     alias, documented as "a Codex-specific extension that points to the
#     installed plugin root" (OpenAI's official Codex hooks reference,
#     learn.chatgpt.com/docs/hooks.md).
#   - None of these is set under Claude Code itself, which is the fallback.
# This keeps hooks/hooks.json identical across all four tools — no per-tool
# arguments, and no risk of a tool's own shell reinterpreting a reminder
# argument (a path, or a leftover command string like "$handoff").
#
# When a flag is present, this exits 2 with a wrap-up procedure on stderr so
# the model surfaces the quota, asks before writing a handoff document if the
# session has unfinished work a later session cannot reconstruct, then
# deletes the flag so the same crossing doesn't surface again on the next
# tool call or turn. It fires again only after CodexBar detects a fresh
# threshold crossing for this provider and writes a new flag.
set -euo pipefail

if [[ -n "${GROK_SESSION_ID:-}" ]]; then
  provider="grok"
elif [[ -n "${COPILOT_CLI:-}" ]]; then
  provider="copilot"
elif [[ -n "${PLUGIN_ROOT:-}" ]]; then
  provider="codex"
else
  provider="claude"
fi

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
[[ "$state_home" == /* ]] || state_home="$HOME/.local/state"
flag_path="${CODEXBAR_QUOTA_FLAG_PATH:-$state_home/codexbar-quota-handoff/quota-low-${provider}.json}"

if [[ ! -f "$flag_path" ]]; then
  exit 0
fi

# Claim the flag with an atomic rename rather than read-then-delete: Stop and
# PostToolUse are both registered on the same script, and PostToolUse fires
# once per tool call, so multiple tool calls finishing in the same parallel
# batch can spawn concurrent invocations of this script for the same
# crossing. A plain `cat` followed by `rm -f` is a TOCTOU race — two
# processes could both read the flag before either deletes it, printing the
# reminder twice. `mv` within one filesystem is atomic, so only one
# process's rename can succeed against a given source path; every other
# concurrent invocation's `mv` fails (source already gone) and it exits 0
# silently instead of duplicating the reminder. Trade-off: a crash between
# the claim and printing the reminder loses that reminder silently instead
# of retrying — acceptable for a non-critical, self-healing notification
# (a fresh crossing writes a new flag regardless), and far rarer than the
# duplicate-print risk this replaces.
claimed_path="${flag_path}.claimed.$$"
if ! mv "$flag_path" "$claimed_path" 2>/dev/null; then
  exit 0
fi

payload="$(cat "$claimed_path")"
rm -f "$claimed_path"

window="$(printf '%s' "$payload" | jq -r '.window // "unknown"')"
usage_percent="$(printf '%s' "$payload" | jq -r '.usagePercent // 0')"
reset_at="$(printf '%s' "$payload" | jq -r '.resetAt // "unknown"')"
pct_display="$(awk -v p="$usage_percent" 'BEGIN { printf "%.0f", (p + 0) * 100 }')"

# A flag can sit unclaimed for a while (e.g. no tool call or Stop fired
# between CodexBar writing it and this hook running next), so by the time we
# get here the reset the payload warned about may already be behind us —
# relaying it then would just confuse the user with a stale window. Try GNU
# `date -d` first, then BSD/macOS `date -j -f`; if neither can parse
# resetAt, fail open (still show the reminder) rather than silently drop a
# real crossing over a format we don't recognize.
if [[ "$reset_at" != "unknown" ]]; then
  reset_epoch="$(date -u -d "$reset_at" +%s 2>/dev/null)" \
    || reset_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$reset_at" +%s 2>/dev/null)" \
    || reset_epoch=""
  if [[ -n "$reset_epoch" ]] && (( reset_epoch < $(date -u +%s) )); then
    exit 0
  fi
fi

# Destination for a handoff document, if the user later agrees to write one.
# Probe only the Skills Manager master copy (~/.agents/skills/to-memory).
# Do not --ensure: the user has not agreed yet, so create no directories.
resolve_handoff_dest() {
  local today skill_md proj_script resolved
  today="$(date +%Y-%m-%d)"
  skill_md="${HOME}/.agents/skills/to-memory/SKILL.md"
  proj_script="${HOME}/.agents/skills/to-memory/scripts/proj-memory-path.sh"

  if [[ -f "$skill_md" ]]; then
    resolved=""
    if [[ -x "$proj_script" ]] \
      && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_PREFIX \
        git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      resolved="$("$proj_script" 2>/dev/null)" || resolved=""
      if [[ -n "$resolved" && "$resolved" == /* ]]; then
        printf '%s/%s-handoff-<topic>.md' "$resolved" "$today"
        return
      fi
    fi
    printf '%s/.agents/memories/%s-handoff-<topic>.md' "$HOME" "$today"
    return
  fi

  printf '%s/%s-quota-handoff.md (never a temp dir)' "$(pwd)" "$today"
}

dest_spec="$(resolve_handoff_dest)"

{
  printf 'CodexBar detected your %s quota is at %s%% used (resets around %s). Tell the user. Once per crossing.\n' \
    "$window" "$pct_display" "$reset_at"
  printf 'Finish in-flight tools. Then, from this conversation only (no extra tools), before your next user-facing reply: if unfinished work a later session could not reconstruct from git/issues/PRs/docs, ask whether to write a handoff document (one-line summary; would go to %s); if none, do not ask or write. That reply is only the quota facts plus that question if any. Then stop.\n' \
    "$dest_spec"
  printf 'If they agree: create a new file at that path (replace <topic> if present; pick a non-colliding name; do not overwrite). Redact secrets; no transcript; reference artifacts; include goal, done, next, suggested skills if any, and this quota reset. Do not invoke to-memory. Reply with the path. If they decline, do not write.\n'
} >&2

exit 2
