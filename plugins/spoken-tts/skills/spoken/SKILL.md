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
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/scripts/spoken.sh" <command>
```

On Codex/Copilot, `CLAUDE_PLUGIN_ROOT` may be `PLUGIN_ROOT`. If both are
unset, the path above is relative to this `SKILL.md`.

## Slash: on / off / setup / toggle

`$ARGUMENTS` is `on`, `off`, `setup`, empty (toggle), or absent. Anything
else is not a speech payload — ask what they meant.

### on

Done when `spoken.sh on` exits 0 (or pending-claim) and you have told the
user this conversation will speak summaries. Do not install packages.

If it asks for setup (no native TTS), stop and say so.

### off

Done when `spoken.sh off` exits 0. Playback stops.

### toggle

Done when `spoken.sh toggle` exits 0 and you report the new state from
`spoken.sh status`.

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
