---
name: spoken
description: >-
  Spoken: read a specific passage the user named (read this aloud)
  by running the plugin CLI. Not for routine per-turn status.
---

# Spoken

Two pipes share one CLI, one global voice config, and the leading word
`spoken`.

CLI (from this skill: `../../scripts/spoken.sh`):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}}/scripts/spoken.sh" <command>
```

On Codex, Copilot, or Antigravity, `CLAUDE_PLUGIN_ROOT` may be `PLUGIN_ROOT`. If both are
unset, the path above is relative to this `SKILL.md`.

## Slash: on / off / setup / toggle / status / test

Always execute the corresponding `spoken.sh` subcommand using your shell tool. Run `spoken.sh` directly; do not read or inspect files in this skill folder.

`$ARGUMENTS` is `on`, `off`, `setup`, `status`, `test` (optionally followed by custom speech text), empty (toggle), or absent. Anything else is not a speech payload — ask what they meant.

### on

Execute `spoken.sh on` using your shell tool.
Done when `spoken.sh on` exits 0 (or pending-claim) and you have told the
user this conversation will speak summaries in the reported locale. Do not install packages.

If it asks for setup (no native TTS), stop and say so.

### off

Execute `spoken.sh off` using your shell tool.
Done when `spoken.sh off` exits 0. Playback stops.

### toggle

Execute `spoken.sh toggle` using your shell tool.
Done when `spoken.sh toggle` exits 0 and you report the new state from
`spoken.sh status`.

### status

Execute `spoken.sh status` using your shell tool.
Done when `spoken.sh status` exits 0 and you report the exact status and locale output by the command.

### test

Execute `spoken.sh test` using your shell tool. Pass user-provided text after `test` as arguments (`spoken.sh test <text>`); if none was given, run `spoken.sh test` with no arguments so it plays the built-in localized test phrase. Do not invent or supply sample text.
Done when `spoken.sh test` exits 0 and you report what was spoken, along with the provider, locale, and voice tested. Do not add a `<spoken>` tag this turn.

### setup

Interview, then persist. Do not enable the session.

1. Provider: run `default-provider`. Offer that first (`edge-tts`). Native
   `say` remains an option on macOS. If they pick `edge-tts`, run
   `ensure-edge-tts` until it succeeds or you have given the install lines.
2. Locale: `zh-TW`, `zh-CN`, `en-US`, `en-GB`, `ja-JP`. Recommend
   `locale-recommend`.
3. Voice: run `voices --provider … --locale …`. Always list every line;
   the first is the recommendation (zh-TW: HsiaoChen / Meijia). Ask them
   to pick. Empty list → setup failed; they install a system voice, switch
   provider, or switch locale.
4. `config-write --provider … --locale … --voice …`
5. `test` (one utterance). Session stays off.

Done when config-show has provider, locale, and voice, and the test ran.

## Named passage

When the user named text to hear (a file, a paste, a quote):

1. Load that text.
2. Pipe it to `spoken.sh speak` (does not require the session on).
3. Do not add a `<spoken>` tag this turn.

Done when `speak` exits 0.

Session summaries are a Stop hook after `/spoken on`; they are not this
branch.
