# Effects: pointer, captions, auto-zoom

Three things are drawn on top of the real page. All are on by default, and
`effects` in `scenario.json` turns any of them off, or keeps the pointer from
hiding itself:

```json
{ "effects": { "zoom": false, "cursor": true, "cursorAutoHide": true, "captions": true } }
```

Only these four keys are accepted, only booleans, and a key you leave out
keeps its default. A typo is refused before a browser opens rather than
silently ignored.

| Effect | On | Off |
| --- | --- | --- |
| `cursor` | A macOS-style arrow travels to each target, swaps to a pointing hand or I-beam while resting on it, fades out when idle, and a click or double-click leaves a fading blue ring | No arrow, and the mouse moves straight to its target instead of sweeping hover states along a path nobody can see |
| `cursorAutoHide` | The pointer fades when idle and while the keyboard is in use (see Pointer) | The pointer stays on screen throughout |
| `captions` | A caption names each interaction while it happens | Nothing is drawn |
| `zoom` | ffmpeg zooms into each click, panning from one to the next when they come close together | No zoom is applied. A `.webm` output is the raw capture; any other container is still re-encoded by ffmpeg. `.clicks.jsonl` and `.zooms.json` are written either way |

Turning `zoom` off does not throw the zoom data away, so you can record once
and decide later:

```bash
node scripts/render-auto-zoom.mjs --video demo.webm --clicks demo.clicks.jsonl --out zoomed.mp4
```

### Zoom clusters

Clicks closer together than 800ms (`MERGE_GAP_MS`) are grouped into a single zoom cluster that pans between targets instead of zooming out and straight back in. For distinct steps to zoom out and back in between each other, keep the step's `pause` at 2500ms or higher (the default pause).

## Pointer

The icon is read off the step's own `action`, not sniffed live from the page:
`click`, `dblclick` and `select` show a pointing hand; `type` shows an
I-beam; `press` and everything else leave the arrow alone. The swap only
happens once the pointer is resting on that step's target, and it reverts
to the arrow as soon as the pointer starts moving to the next one.

A `click` leaves one fading ring at the click point; a `dblclick` leaves
two, about 150ms apart, so a double-click reads as one on screen. `type`
and `select` still perform a real click to focus the target, but that
click leaves no ring — only `click` and `dblclick` do.

Like the macOS pointer, it fades out after resting 1.5s, and hides as soon
as a `type` or `press` step starts using the keyboard; the next move or
click brings it back. A page that loads mid-step starts with it hidden
rather than flashing it back where it rested. `"cursorAutoHide": false`
keeps it on screen instead.

## Captions

Every interaction step is captioned: `click`, `dblclick`, `type`, `select`
and `press`. The caption holds for the whole step, so an instant keypress
still stays on screen long enough to read. It appears once the pointer
reaches the target, before the click, and a step that loads another page
removes it then, rather than leaving it over the page it lands on.

`wait`, `expect` and `goto` have nothing to name, so they are captioned only
when the step carries its own `caption`. Such a caption holds until the step
ends, however many times the page reloads meanwhile: these steps are where
the viewer watches the page change, and a reload loop or a slow redirect is
often the very thing the recording shows. A `goto` caption is up before the
page it opens goes blank and stays through that page's `pause`, which a
`goto` without a caption does not wait out; an `expect` caption shows while
the element is still missing.

```json
{ "action": "goto", "url": "https://example.com/?q=1", "caption": "Open a URL with a query", "pause": 1500 },
{ "action": "wait", "ms": 8000, "caption": "The page keeps reloading" }
```

A caption sits just under the element the step acts on, not at the bottom of
the page. Auto-zoom crops a 1.5x window around the click, and a caption pinned
to the bottom edge falls outside that crop exactly when the viewer is looking
hardest. A step with no element — `press`, `wait`, `goto`, and `expect`,
whose element may not exist yet — centres its caption at the bottom instead.

A long caption wraps rather than running off the edge: it is at most 720px
wide, or the viewport less a 16px gutter each side on a phone, and it moves
toward the centre as far as that width needs. A narrow viewport also gets a
smaller font.

Only you know what a click opens, so a step can move its caption out of the
way with `captionPlacement`. The default, `auto`, puts the caption under the
target, or above it near the bottom edge. `above` and `below` force a side,
and `bottom` centres it at the foot of the viewport. A menu that drops down
under its toggle is the usual reason:

```json
{ "action": "click", "role": "button", "name": "Menu", "captionPlacement": "bottom" }
```

`above` is not moved back on screen for a target near the top edge. Use
`bottom` there instead. `bottom` lies outside the auto-zoom crop unless the
target is itself near the bottom, so the caption shows only while the view is
not zoomed in.

The wording is generated from the step — a verb plus what it acts on, types,
or presses. `captionLocale` picks the wording. English, Traditional Chinese (`zh-TW`) and
Japanese (`ja`) ship; anything else falls back to English. Each locale carries
a template rather than a verb, because word order differs: `Click Save`,
`點擊 Save`, `Save をクリック`. **Set it to the language
of the conversation that asked for the recording**: a script cannot know who
the video is for, so the agent writing `scenario.json` decides.

A `type` step captions a secret as dots. When its field is `type="password"`
or carries `autocomplete` `current-password`, `new-password` or
`one-time-code`, the caption reads `Type ••••••••` — eight dots whatever the
length. `"sensitive": true` masks any other field the page cannot mark, such
as an API key, and a step whose text comes from `textEnv` is always masked.

Any step can replace its generated caption. A secret step's own `caption` is
shown as written, so it names the field rather than the value:

```json
{ "action": "press", "keys": "Control+k", "caption": "按下 Ctrl + K 開啟搜尋" }
```

A combination key is rendered as key symbols rather than Playwright's syntax:
`Meta+Shift+p` reads as `⌘ + ⇧ + P`.

## Status bar

Playwright records the viewport, never the browser's address bar. When the
address is the evidence — a redirect loop, a query that keeps growing, a
route a click should have changed — `statusBar` draws it across the top of
the page. It is off unless the scenario asks:

```json
{ "statusBar": true }
{ "statusBar": { "label": "Before (main)", "mask": ["ticket"] } }
```

`label` is a fixed first line, handy for telling a before and an after
recording apart. The address below it is redrawn every time the page
navigates, a reload or a history or hash change included, and is shown
exactly as the page has it: `%23%2F` stays `%23%2F`. A long one wraps and is
cut off after three lines.

The value of any parameter named `token`, `access_token`, `id_token`,
`refresh_token`, `code`, `key`, `api_key`, `secret`, `password`, `sig`,
`signature` or `session`, in any case, is drawn as eight dots, in the query
and in the fragment alike (`#/reset?token=…`, `#access_token=…`), and so is
any `user:password@`. `mask` adds names of your own. A secret in the path
itself, such as `/reset/<token>`, is not recognised: record such a page
without the bar, or start from an address that carries none.

The bar covers the top of the page, and a caption that would sit above a
target under it goes below instead. Auto-zoom crops to a window around each
click, which usually leaves the bar out; the recorder warns whenever a
recording with the bar zooms, and `"effects": { "zoom": false }` keeps it on screen throughout. A
walkthrough that only waits and reloads has no click to zoom on anyway.

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
