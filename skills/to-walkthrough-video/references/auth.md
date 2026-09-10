# Recording behind a sign-in

`record.mjs` opens a clean browser, so a system that needs a session shows you
its login page and nothing else. Sign in once by hand, save the browser's
storage state, and record with that state loaded. The sign-in never reaches the
video.

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

## 2. Point the scenario at a signed-in landing page

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

## 3. Record

```bash
node scripts/record.mjs --scenario scenario.json --out demo.webm \
  --storage-state auth.json
```

The path is a flag, never a scenario field, so `scenario.json` stays safe to
commit and share.

When `auth.expect` does not appear, recording stops before the video is kept
and tells you to sign in again. A saved state expires on the server's schedule,
not on any clock this skill can read.

## Limits

- **sessionStorage is not covered.** Playwright's storage state carries
  cookies, localStorage, IndexedDB and WebAuthn credentials. A system that
  keeps its token in `sessionStorage` — MSAL's default among them — cannot be
  recorded this way. Check DevTools › Application after signing in.
- **The recording shows whatever the account can see.** There is no masking in
  video; `mask` exists only on Playwright's screenshot APIs. Record with a
  test account holding fixture data, not with a real one.
- **What the scenario carries is yours to decide.** `record.mjs` does not
  inspect what a step types, so a walkthrough that fills a login form on camera
  records exactly as written. The storage state above exists so you rarely need
  to: it keeps the credential out of a file you might commit, and the sign-in
  out of the video.

## Trying it offline

`examples/site/` is a fixture with a public page, a sign-in form that accepts
anything, and a cookie-gated page:

```bash
node examples/site/serve.mjs                 # http://localhost:4173/
npx playwright open --save-storage=auth.json http://localhost:4173/login
node scripts/record.mjs --scenario examples/scenario-auth.json \
  --out demo.webm --storage-state auth.json
```

`examples/scenario.json` records the public page, for the mode that needs no
state at all.
