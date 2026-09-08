---
name: to-walkthrough-video
description: >-
  Record a website walkthrough video with auto-zoom on clicks.
  Use when the user asks to record a walkthrough, or invokes
  /to-walkthrough-video.
---

# to-walkthrough-video

Record a website walkthrough with Playwright. Every click draws a pointer,
a bounce, and a blue echo ring. ffmpeg applies auto-zoom from the click
log; without ffmpeg, WebM still keeps the pointer and echo.

Scripts live in `scripts/` next to this file.

## Prerequisites

- Node.js
- Playwright Chromium resolvable from the recording cwd:
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
  "steps": [
    { "action": "wait", "ms": 800 },
    { "action": "click", "role": "link", "name": "More information" },
    { "action": "type", "role": "textbox", "name": "Search", "text": "SSH", "pause": 1800 },
    { "action": "select", "role": "combobox", "name": "Language", "value": "English" }
  ]
}
```

2. **Record.** From a directory that can `import('playwright')`:

```bash
node scripts/record.mjs --scenario scenario.json --out demo.webm
```

Leave this step when the video, `demo.clicks.jsonl`, and `demo.zooms.json`
exist and the zoom file has `"status": "ok"` with one region per click
cluster. Without ffmpeg, WebM is the raw capture (pointer and echo, no
zoom) and the zoom file still records the clusters.

3. **Hand back.** Give the user the video path.

## Defaults

Viewport is 1280×720 CSS pixels (`deviceScaleFactor` 1). Override with
`scenario.viewport` or `--width`/`--height` (even numbers; odd values
round up). After each click, pause 2500ms so clusters split; override
with `scenario.pauseMs`, `--pause-ms`, or per-step `pause`. Clicks
≤2500ms apart share one zoom; each region is padded ±500ms and scaled
1.5×. Flags: `record.mjs --help`.
