# Effects: pointer, captions, auto-zoom

Three things are drawn on top of the real page. All three are on by default,
and `effects` in `scenario.json` turns any of them off:

```json
{ "effects": { "zoom": false, "cursor": true, "captions": true } }
```

Only these three keys are accepted, only booleans, and a key you leave out
keeps its default. A typo is refused before a browser opens rather than
silently ignored.

| Effect | On | Off |
| --- | --- | --- |
| `cursor` | An arrow travels to each target, swaps to a hand or text-input icon while resting on it, and a click or double-click leaves a fading blue ring | No arrow, and the mouse moves straight to its target instead of sweeping hover states along a path nobody can see |
| `captions` | A caption names each interaction while it happens | Nothing is drawn |
| `zoom` | ffmpeg zooms into each click cluster | No zoom is applied. A `.webm` output is the raw capture; any other container is still re-encoded by ffmpeg. `.clicks.jsonl` and `.zooms.json` are written either way |

Turning `zoom` off does not throw the zoom data away, so you can record once
and decide later:

```bash
node scripts/render-auto-zoom.mjs --video demo.webm --clicks demo.clicks.jsonl --out zoomed.mp4
```

## Pointer

The icon is read off the step's own `action`, not sniffed live from the page:
`click`, `dblclick` and `select` show a hand; `type` shows a text-input
caret; `press` and everything else leave the arrow alone. The swap only
happens once the pointer is resting on that step's target, and it reverts
to the arrow as soon as the pointer starts moving to the next one.

A `click` leaves one fading ring at the click point; a `dblclick` leaves
two, about 150ms apart, so a double-click reads as one on screen. `type`
and `select` still perform a real click to focus the target, but that
click leaves no ring — only `click` and `dblclick` do.

## Captions

Every interaction step is captioned: `click`, `dblclick`, `type`, `select`
and `press`. `wait` and `goto` are not. The caption holds for the whole step,
so an instant keypress still stays on screen long enough to read.

A caption sits just under the element the step acts on, not at the bottom of
the page. Auto-zoom crops a 1.5x window around the click, and a caption pinned
to the bottom edge falls outside that crop exactly when the viewer is looking
hardest. A step with no element — `press` — centres its caption instead.

The wording is generated from the step — a verb plus what it acts on, types,
or presses. `captionLocale` picks the wording. English, Traditional Chinese (`zh-TW`) and
Japanese (`ja`) ship; anything else falls back to English. Each locale carries
a template rather than a verb, because word order differs: `Click Save`,
`點擊 Save`, `Save をクリック`. **Set it to the language
of the conversation that asked for the recording**: a script cannot know who
the video is for, so the agent writing `scenario.json` decides.

Any step can replace its generated caption:

```json
{ "action": "press", "keys": "Control+k", "caption": "按下 Ctrl + K 開啟搜尋" }
```

A combination key is rendered as key symbols rather than Playwright's syntax:
`Meta+Shift+p` reads as `⌘ + ⇧ + P`.

## The `press` step

```json
{ "action": "press", "keys": "Control+k" }
```

It takes no locator, because a shortcut acts on the page rather than an
element. Keys use Playwright's own syntax — `Control+k`, `Meta+Shift+P`,
`Enter`, `Escape`.

This is the step whose effect the screen may not show at all, which is why
captions matter most here.

## What a recording cannot show

Playwright never runs an input method editor. Typing CJK text sends the
characters straight into the field: four `insertText` events for 你好世界, no
key presses and no composition. The candidate window a real user would see
never appears, and the text simply materialises. A caption is the only thing
that explains where it came from.

## Why Playwright 1.59

Capture runs through `page.screencast`, added in 1.59, rather than the
context-level `recordVideo`. Recording therefore starts where the walkthrough
starts instead of when the page is created, so no preamble has to be trimmed
back off, and the same call works on a page that already exists. Captions use
`screencast.showOverlay` from the same release.

`record.mjs` says so plainly when the installed Playwright is older, rather
than failing somewhere deep.
