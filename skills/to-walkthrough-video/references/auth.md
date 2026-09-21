# Recording behind a sign-in

`record.mjs` opens a clean browser, so a system that needs a session shows you
its login page and nothing else. There are two ways past it, and the sign-in
reaches the video in neither.

**Sign in once, record many times.** Save the browser's storage state and load
it at record time. Unattended afterwards, so this is the one for a walkthrough
you re-record. It leaves a file on disk that can impersonate the account.

**Sign in at the start of each recording.** `--sign-in` opens a real browser
window, waits for you, and starts recording only once you are in. Nothing is
saved anywhere, but somebody has to be at the keyboard every time. This is
also the only way past a system that keeps its session in `sessionStorage`,
which a storage state cannot carry at all.

## 1. Save the state

Playwright ships the whole flow. Nothing in this skill replaces it:

```bash
npx playwright open --save-storage=auth.json https://app.example.com
```

A browser opens. Sign in yourself — password, OIDC, MFA, whatever the system
asks. Close the window; Playwright writes cookies, localStorage and IndexedDB
to `auth.json`.

`open` needs a person at a headed browser. An agent drives the same sign-in
with Playwright and writes the same file, which is what the recording side
actually reads:

```js
const context = await browser.newContext();
// ... sign in on the page ...
await context.storageState({ path: "auth.json", indexedDB: true });
```

Pass `indexedDB: true`. The CLI includes it, the API does not, and a token kept
there is dropped without it.

Keep that file out of the repository. It can impersonate the account that made
it for as long as the session lives:

```bash
echo 'auth.json' >> .gitignore
```

`record.mjs` warns when the file sits in a git work tree and is not ignored.

## 2. Explore through the same state

Writing `scenario.json` (SKILL.md step 1) needs locators from the signed-in
pages, not the login screen. Reuse the `auth.json` from step 1 with
`playwright-cli` instead of signing in again:

```bash
playwright-cli open                        # blank browser, no URL yet
playwright-cli state-load auth.json
playwright-cli goto https://app.example.com/dashboard
playwright-cli snapshot
```

Order matters: `state-load` attaches to the browser `open` already started,
so `open` must come first and without a URL — `open <url>` on its own starts
a fresh, signed-out browser and any state loaded before it is discarded with
it. Only `goto` after the load lands on a page carrying the session.

If `playwright-cli` also does step 1's sign-in — a human at the keyboard,
`open` then wait — two defaults bite: `open` starts headless, so the person
waiting sees nothing until it's reopened with `--headed`; and nothing is
saved unless `playwright-cli state-save auth.json` runs before moving on.
Skip that save and this step still works — the browser stays signed in — but
the record step below has no file to load and falls back to a second
sign-in. One login should cover sign-in, explore, and record.

## 3. Point the scenario at a signed-in landing page

`scenario.url` is the first screen you want on camera, not the login page. Add
an `auth.expect` locator that is visible only once signed in — an account menu,
a greeting, a sign-out button. It takes the same shape as a step: `role` plus
`name`, or `selector`, `text`, or `label`.

```json
{
  "url": "https://app.example.com/dashboard",
  "auth": { "expect": { "role": "button", "name": "Account" } },
  "steps": [{ "action": "click", "role": "link", "name": "Reports" }]
}
```

The locator is required in this mode. Without it a dead session records a
walkthrough of the login page and nobody notices until playback.

## 4. Record

```bash
node scripts/record.mjs --scenario scenario.json --out demo.mp4 \
  --storage-state auth.json
```

The path is a flag, never a scenario field, so `scenario.json` stays safe to
commit and share — unless a step types a secret as `text`; see Limits.

When `auth.expect` does not appear, recording stops before the video is kept
and tells you to sign in again. A saved state expires on the server's schedule,
not on any clock this skill can read.

## Signing in by hand instead

```bash
node scripts/record.mjs --scenario scenario.json --out demo.mp4 --sign-in
```

A browser window opens on `scenario.url`, which the system will bounce to its
own login screen. Sign in however it asks — password, OIDC, MFA. `record.mjs`
watches `auth.expect` and starts capturing the moment it appears, so no frame
of the sign-in is in the file. It waits three minutes, then gives up rather
than record a login screen.

`--sign-in` needs a screen to put the window on. Over SSH or in CI it says so
rather than failing obscurely. It cannot be combined with `--storage-state`:
one makes a session, the other loads one.

To check it end to end against the fixture:

```bash
node examples/site/serve.mjs
node scripts/record.mjs --scenario examples/scenario-auth.json --out demo.mp4 --sign-in
```

Sign in with anything, and confirm the first frame of `demo.mp4` is already
the dashboard.

## Recording the window you already signed in on

`--connect` records a page you are already signed in on, so a site you know
nothing about needs one sign-in for the whole job: exploring and recording share
the same window, and a session held only in page memory or `sessionStorage`
survives because the browser never closes.

Start a Chromium-based browser with a debugging port and sign in there, then
attach `playwright-cli` for the snapshots and point `record.mjs` at the same
endpoint:

```bash
open -na "Google Chrome" --args --remote-debugging-port=9222 \
  --no-first-run --no-default-browser-check \
  --user-data-dir="$(mktemp -d)" https://app.example.com
curl -s http://127.0.0.1:9222/json/list   # a "type": "page" entry means it is up
playwright-cli attach --cdp http://127.0.0.1:9222
node scripts/record.mjs --scenario scenario.json --out demo.mp4 \
  --connect http://127.0.0.1:9222
```

A fresh `--user-data-dir` shows Chrome's first-run dialog (default browser,
usage statistics) unless the two `--no-` flags are passed. An agent sees no
window, so check `/json/list` before asking the person to sign in: an empty
list means the browser did not come up.

`record.mjs` records the page that is open, at the window's own size, and
never navigates, reloads or closes it. `scenario.url` is not opened, so the
first step must be reachable from the screen you leave the window on, and
`auth.expect` must already be visible there. Anything you clicked through while
exploring is still in the window: data you added is on screen, and the start
frame is wherever you stopped. Put the window on the screen you want as the
first frame, by clicking, before recording. `--connect` cannot be combined
with `--sign-in` or `--storage-state`.

Recording leaves the window as it ended, and a flow that creates data leaves
that data in the account. To record again, delete what the last take added, or
start a fresh browser and sign in once more. The window stays open for the
person to close.

## Limits

- **sessionStorage is not covered by a saved state.** Playwright's storage
  state carries cookies, localStorage, IndexedDB and WebAuthn credentials. A
  system that keeps its token in `sessionStorage` — MSAL's default among them —
  cannot be reloaded from a file at all. Use `--sign-in` for those: the browser
  never closes, so the session never leaves. Check DevTools › Application after
  signing in to find out which kind you have.
- **A page load can end an in-memory or `sessionStorage` sign-in.** Under
  `--sign-in`, a `goto` step, a reload, or a `playwright-cli goto` while
  exploring drops that session and lands back on the login page. Navigate by
  clicking links inside the page after the sign-in. The exploring window and
  the recording window are separate sessions, so each needs its own sign-in.
- **The recording shows whatever the account can see.** There is no masking in
  video; `mask` exists only on Playwright's screenshot APIs. Record with a
  test account holding fixture data, not with a real one.
- **What the scenario carries is yours to decide.** A walkthrough may fill a
  login form on camera; its caption shows dots (`references/effects.md`,
  Captions). The value itself sits in `scenario.json` unless the step reads it
  with `"textEnv": "DEMO_PASSWORD"`. The person exports that variable in their
  own shell; `record.mjs` refuses to start while it is unset, so check it with
  `[ -n "${DEMO_PASSWORD:-}" ]`. Error output leaves out what any `type` step
  types, so it is safe to paste. The storage state above keeps the sign-in out
  of the video entirely.

## Trying it offline

`examples/site/` is a fixture with a public page, a sign-in form that accepts
anything, and a cookie-gated page:

```bash
node examples/site/serve.mjs                 # http://localhost:4173/
npx playwright open --save-storage=auth.json http://localhost:4173/login
node scripts/record.mjs --scenario examples/scenario-auth.json \
  --out demo.mp4 --storage-state auth.json
```

`examples/scenario.json` records the public page, for the mode that needs no
state at all.
