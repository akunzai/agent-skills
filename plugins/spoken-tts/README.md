# spoken-tts

Opt-in per-conversation spoken summaries, plus a CLI that speaks a named
passage. Default is off. `/spoken on` enables **this conversation only**.
Claude Code lists the skill as `/spoken-tts:spoken`.

- Session on: a Stop hook speaks the last `<spoken>…</spoken>` line.
  Auto summaries are a de-identified status: no credentials, and no
  personal identifiers unless this turn asked to hear them.
- Named passage: the skill runs `spoken.sh speak` without enabling the session.
  CLI `test` and `speak` wait until playback finishes; the Stop hook does not.
- Providers: `edge-tts` (recommended) and macOS `say`.

## Install

Requires `jq`. Native TTS needs `say` (macOS). Setup recommends `edge-tts`;
`/spoken setup` installs it when you pick that provider
(`mise use -g -y pipx:edge-tts` when mise is present, else `uv` / `pipx`).
Playback on Linux or Windows needs `mpv` or `ffplay` on PATH
(`scoop bucket add extras && scoop install mpv`).
`locale-recommend` reads the OS UI language on macOS and Windows before
`LANG`. On Windows it uses the display-language override, then prefers a
non-English tag in the user language list (`en-US` then `zh-Hant-TW`
becomes `zh-TW`).

From the repository root:

```bash
bash scripts/setup.sh --plugin spoken-tts
```

Or enable `spoken` from this marketplace in Claude Code, Copilot, or Cursor.
Codex uses `.agents/plugins/marketplace.json`.
Antigravity CLI installs via:
```bash
agy plugin install ./plugins/spoken-tts
# or remote github
agy plugin install https://github.com/akunzai/agent-skills/tree/main/plugins/spoken-tts
```

## Config

- Config: `${XDG_CONFIG_HOME:-$HOME/.config}/spoken-tts/config.json`
- Session flags: `${XDG_STATE_HOME:-$HOME/.local/state}/spoken-tts/`
- Leftover `${XDG_CONFIG_HOME:-$HOME/.config}/spoken/config.json` is moved
  once when the new path is missing.

## Checks

```bash
bash tests/spoken-manifest.sh
bash tests/spoken-cli.sh
mise run lint
```
