---
name: to-walkthrough-video
description: >-
  Record a website walkthrough video with auto-zoom on clicks.
  Use when the user asks for a walkthrough, when a PR, MR, or issue
  needs a recording of a web flow, or on /to-walkthrough-video.
---

# to-walkthrough-video

Record a website walkthrough with Playwright.

Scripts live in `scripts/` next to this file.

## Prerequisites

- Node.js or Bun (`bun scripts/record.mjs` works too; under Yarn PnP, run `yarn node scripts/record.mjs`)
- Playwright 1.59+ with Chromium (global npm/pnpm/Yarn Classic/Bun, cwd, or `PLAYWRIGHT_DIR`)
- `ffmpeg` on PATH for auto-zoom (both `.webm` and `.mp4`), and whenever `.mp4` output is requested

Check first with `node scripts/record.mjs --check-prereqs`. Exit 0 means recording works, not that ffmpeg is present: read the `ffmpeg:` line. Where it says missing, check `command -v ffmpeg` and `mise ls ffmpeg` before installing, since a mise-managed ffmpeg can exist yet be off this shell's PATH.

When missing, ask the user for confirmation before installing:
- Playwright: recommend `npm i -g playwright && npx playwright install chromium` (global avoids repo pollution; or `-D`).
- `ffmpeg` (for `.mp4` or auto-zoom): recommend `mise use -g ffmpeg` (or platform manager `brew`/`apt`/`winget`, or installing `mise`). Or ask if the user prefers degrading to raw `.webm` without auto-zoom.

## Workflow

1. **Scenario.** A spoken brief is enough. Behind a sign-in: save state once
   with `npx playwright open --save-storage=auth.json <url>`, then explore
   and record through that state — the anonymous page is only ever a login
   screen. `auth.expect` must be visible only when signed in, and record
   with `--storage-state auth.json`, or pass `--sign-in` to sign in by hand
   at the start of the recording instead, or `--connect` to record a window
   already signed in on, so a site you cannot know ahead needs one sign-in
   for both exploring and recording. See `references/auth.md`. Explore
   the live page and write `scenario.json` with the start URL and every
   click, in order. Each click needs a locator (`role`+`name`, `selector`,
   `text`, or `label`). Discover locators with `playwright-cli snapshot`
   when that command is on PATH; otherwise a Playwright script. Reuse a
   webwright run only when one already exists for this flow — webwright
   launches a fresh, stateless browser each time and cannot carry a
   signed-in session past a login wall. Leave this step when the file is on
   disk.

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

Prefer `role` + `name` over `selector`: a caption falls back to the raw
selector text (`Click nav a[href…]`) when a step has no name, label or text, so
give a `selector` step its own `caption`. A `click` waits up to 15 seconds for
its target to be visible (`timeout` changes that per step). To wait for
something without touching it, such as the row a submit just added, use
`{ "action": "expect", "text": "Saved" }`; `state` may be `"hidden"`. When a
step fails the error names it (`step 3 of 5 {...}`) and `<out>.failure.png` and
`<out>.failure.aria.txt` show what the page looked like. When the
flow creates data, do it once while exploring and note where it lands (a later
page, a filter, below the fold) so the last step targets the right place.
A secret a step types goes in `"textEnv": "VAR"` rather than `text`, and a
field the page does not mark as a password (an API key) gets
`"sensitive": true` so its caption shows dots. See `references/auth.md`.

Pointer, captions and auto-zoom are on; `effects` turns any off. Set
`captionLocale` to the language of the conversation asking for the
recording, or, for evidence on an issue or request, to the language the
repo writes those in. See `references/effects.md`.

For mobile/tablet, set `scenario.device` to `"phone"` (newest iPhone Pro) or
`"tablet"` (iPad Mini, narrower than iPad Pro so a collapsed nav still shows
— see `DEVICE_PRESET_ALIASES` in `record.mjs`) rather than shrinking
`viewport`. Also accepts an exact Playwright device name. A touch device
taps `click`/`type`/`select` targets, so touch-only handlers fire;
`dblclick` and a non-left `button` still use the mouse.
`scenario.viewport`/`--width`/`--height` still override it.
`scenario.locale` (e.g. `"zh-TW"`) sets the browser language; Playwright
otherwise starts in `en-US`, so set it whenever the site is localized.
`"ignoreHTTPSErrors": true` accepts a self-signed local certificate.

2. **Record.** From a directory that can `import('playwright')`:

```bash
node scripts/record.mjs --scenario scenario.json --out demo.mp4
```

The `--out` extension picks the container. Default to `.mp4` (smallest, and
plays in every browser and PR preview); use `.webm` only without ffmpeg or
when the user asks for it.

Leave this step when the video, `demo.clicks.jsonl`, and `demo.zooms.json`
exist and the zoom file has `"status": "ok"` with one region per click
cluster. Without ffmpeg, output is raw `.webm` without auto-zoom (pointer and
click echo are still included), and the zoom file still lists the clusters.

A passing zoom file says nothing about the picture. Before handing back, pull a
frame from the last step (`ffmpeg -sseof -1 -i demo.mp4 -frames:v 1 last.png`)
and look at it: the result the flow was meant to end on, such as the new row,
must be in frame, and a page you scrolled must have reached its end.

3. **Hand back.** Give the user the video path.

## Defaults

Viewport is 1280×720 CSS pixels (`deviceScaleFactor` 1). Override with
`scenario.viewport` or `--width`/`--height` (even numbers; odd values
round up). After each click, pause 2500ms so clusters split; override
with `scenario.pauseMs`, `--pause-ms`, or per-step `pause`. Clicks
≤2500ms apart share one zoom only if they also land within 0.35 of the
normalized viewport (a click far enough away, e.g. a corner toolbar
button after a center click, starts its own zoom even if the pause was
shorter — otherwise the camera would freeze on the earlier click and
never pan to follow the cursor there). Each region is padded ±500ms
and scaled 1.5×. Flags: `record.mjs --help`.
