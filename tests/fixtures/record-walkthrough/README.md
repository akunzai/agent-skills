# record-walkthrough fixture

An offline site for `tests/record-walkthrough.sh` and for trying the skill by
hand: a public page, a sign-in form that accepts anything, and a cookie-gated
page. It lives outside `skills/record-walkthrough/` so an agent writing a
real scenario has no ready-made one to copy.

Run these from `skills/record-walkthrough/`:

```bash
F=../../tests/fixtures/record-walkthrough
node $F/site/serve.mjs                       # http://localhost:4173/
```

| Scenario | Mode |
| --- | --- |
| `scenario.json` | Public page, no state |
| `scenario-auth.json` | Behind the sign-in: `--storage-state auth.json` or `--sign-in` |
| `scenario-login.json` | Signs in on camera, password from `DEMO_PASSWORD`, captioned as dots |
| `scenario-mobile.json` | Phone device preset |
| `scenario-shortcut.json` | Keyboard shortcut with its own caption |

```bash
# Saved state
npx playwright open --save-storage=auth.json http://localhost:4173/login
node scripts/record.mjs --scenario $F/scenario-auth.json --out demo.mp4 --storage-state auth.json

# Sign in by hand; the first frame of demo.mp4 should already be the dashboard
node scripts/record.mjs --scenario $F/scenario-auth.json --out demo.mp4 --sign-in

# Sign in on camera
DEMO_PASSWORD=anything node scripts/record.mjs --scenario $F/scenario-login.json --out demo.mp4
```
