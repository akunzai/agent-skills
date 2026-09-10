---
name: to-walkthrough-video
description: >-
  Record a website walkthrough video with auto-zoom on clicks.
  Use when the user asks to record a walkthrough, or invokes
  /to-walkthrough-video.
---

# to-walkthrough-video

Record a website walkthrough with Playwright.

Scripts live in `scripts/` next to this file.

## Prerequisites

- Node.js
- Playwright 1.59+ with Chromium, resolvable from the recording cwd:
  `npm i -D playwright && npx playwright install chromium`
- `ffmpeg` on PATH for auto-zoom, and for `.mp4` output

## Workflow

1. **Scenario.** A spoken brief is enough. Explore the live page and write
   `scenario.json` with the start URL and every click, in order. Each click
   needs a locator (`role`+`name`, `selector`, `text`, or `label`). Discover
   locators with `playwright-cli snapshot` when that command is on PATH;
   otherwise a Playwright script. Reuse a webwright run only when one
   already exists for this flow. Leave this step when the file is on disk.

```json
{
  "url": "https://example.com",
  "captionLocale": "en",
  "auth": { "expect": { "role": "button", "name": "Account" } },
  "steps": [
    { "action": "wait", "ms": 800 },
    { "action": "click", "role": "link", "name": "More information" },
    { "action": "press", "keys": "Control+k" },
    { "action": "type", "role": "textbox", "name": "Search", "text": "SSH", "pause": 1800 },
    { "action": "select", "role": "combobox", "name": "Language", "value": "English" }
  ]
}
```

Pointer, captions and auto-zoom are on; `effects` turns any off. Set
`captionLocale` to the language of the conversation asking for the
recording. See `references/effects.md`.

Behind a sign-in: save state once with `npx playwright open
--save-storage=auth.json <url>`, then record with `--storage-state
auth.json`, or pass `--sign-in` to sign in by hand at the start of the
recording. `auth.expect` must be visible only when signed in. See
`references/auth.md`.

2. **Record.** From a directory that can `import('playwright')`:

```bash
node scripts/record.mjs --scenario scenario.json --out demo.webm
```

Leave this step when the video, `demo.clicks.jsonl`, and `demo.zooms.json`
exist and the zoom file has `"status": "ok"` with one region per click
cluster. Without ffmpeg, WebM is the raw capture and the zoom
file still lists the clusters.

3. **Hand back.** Give the user the video path.

## Defaults

Viewport is 1280×720 CSS pixels (`deviceScaleFactor` 1). Override with
`scenario.viewport` or `--width`/`--height` (even numbers; odd values
round up). After each click, pause 2500ms so clusters split; override
with `scenario.pauseMs`, `--pause-ms`, or per-step `pause`. Clicks
≤2500ms apart share one zoom; each region is padded ±500ms and scaled
1.5×. Flags: `record.mjs --help`.
