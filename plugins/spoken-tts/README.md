# spoken-tts

Opt-in per-conversation spoken summaries, plus a CLI that speaks a named
passage. Default is off. `/spoken on` enables **this conversation only**.
Claude Code lists the skill as `/spoken-tts:spoken`.

- Session on: a Stop hook speaks the last `<spoken>…</spoken>` line.
- Named passage: the skill runs `spoken.sh speak` without enabling the session.
- Providers: `edge-tts` (recommended) and macOS `say`.

## Install

Requires `jq`. Native TTS needs `say` (macOS). Setup recommends `edge-tts`;
`/spoken setup` installs it when you pick that provider
(`mise use -g -y pipx:edge-tts` when mise is present, else `uv` / `pipx`).

From the repository root:

```bash
bash scripts/setup.sh --plugin spoken-tts
```

Or enable `spoken` from this marketplace in Claude Code, Copilot, or Cursor.
Codex uses `.agents/plugins/marketplace.json`.

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
