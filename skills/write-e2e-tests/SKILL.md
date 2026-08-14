---
name: write-e2e-tests
description: >-
  Use when converting a completed webwright browser-exploration run into a
  durable, checked-in Playwright Test e2e spec — mapping its plan.md
  Critical Points to assertions and validating the result is stable and
  CI-discoverable. Browser-driven UI flows only; not for API-level
  end-to-end tests.
---

# Write E2E Tests

Converts a finished [webwright](https://github.com/microsoft/Webwright) run
into a standalone Playwright Test spec. Webwright is Microsoft Research's
browser-automation Claude Code skill; install it from that repo if it isn't
already available. Its own Plan → Explore → Author → Execute → Self-verify →
Done workflow is the exploration engine, unchanged — this skill starts only
after that run has completed, and adds exactly one capability: turning it
into a test that lives in the project's e2e suite and runs again on its own.

## Scope

**Browser-driven UI flows only** — not API-level end-to-end tests. The
output is always a Playwright Test spec — no per-project detection of
another framework, no cross-framework translation.

## Workflow

1. **Check webwright is installed.** If not, guide the user through
   installing it and wait for their explicit confirmation before proceeding.

2. **Check Playwright Test is set up** in the target project. No
   `@playwright/test` dependency or `playwright.config` at all — stop and
   report this. Don't install or scaffold it yourself; that's the user's
   call.

3. **Convert.** Take a webwright run that has already finished — its
   `plan.md` and `final_script.py` — and produce a standalone Playwright
   Test spec file. How to handle a scan hit is in
   [references/security.md](references/security.md).
   - **Scan input.** Run `scripts/scan-secrets.sh` on `final_script.py`.
     Non-zero exit: follow that doc. A visual read of the script is not
     a scan.
   - **Map and draft.** Map each Critical Point in `plan.md` one-to-one to an
     `expect()` assertion; that mapping is the whole of the conversion,
     don't re-derive what to assert from scratch. Put credential values
     in `process.env`; leave selectors and non-credential fixtures as
     literals.
   - **Scan output.** Run `scripts/scan-secrets.sh` on the drafted spec
     before writing it. Non-zero exit: follow that doc. Do not write a
     spec the script rejects.
   Place the spec in the project's existing e2e test directory (its
   Playwright config's `testDir`, or the project's established
   convention), named after the flow being converted.

4. **Validate.** Run all three gates, in order:
   - **Run** — execute the generated spec once; it passes.
   - **Stable** — re-run it 3 consecutive times; all 3 pass. Confirms the
     flow isn't flaky.
   - **Discoverable** — the project's test-run/CI configuration finds the
     new spec file.

5. **On failure**, attempt an automatic fix and re-validate, up to 2 attempts.
   Still failing after that — stop and report the failure and its likely
   cause. Don't hand back a spec that hasn't passed all three gates.
