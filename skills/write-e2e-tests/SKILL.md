---
name: write-e2e-tests
description: >-
  Use when the user wants browser UI e2e as a Playwright Test spec —
  converting a completed webwright run, or unblocking a missing
  Playwright toolchain or webwright run first. Not for API-level end-to-end
  tests.
---

# Write E2E Tests

Turns a browser UI flow into a checked-in Playwright Test spec.
[Webwright](https://github.com/microsoft/Webwright) is the exploration engine:
it produces `plan.md` and `final_script.py`. This skill unblocks a missing
toolchain or run after confirmation, then converts.

## Scope

The output is always a Playwright Test spec — no per-project detection of
another framework, no cross-framework translation. An existing Cypress or
Selenium suite stays; confirm before adding Playwright beside it.

## Workflow

1. **Inventory.** In the target project, mark each of these present or
   absent: a JS package manifest and its package manager; `@playwright/test`
   and `playwright.config`; the webwright skill; a qualifying run; another
   e2e stack (Cypress, Selenium); existing CI files; webwright artifact
   paths git still tracks. Leave this step when every item is marked. No
   package manifest — stop and report.

2. **Toolchain.** If Playwright, browsers, or webwright are missing, confirm
   once for those items and follow
   [references/setup.md](references/setup.md). Another e2e stack without
   Playwright — confirm adding Playwright beside it.

3. **Find a qualifying run.** Search `outputs/`, `final_runs/`, and any
   path the user named for `plan.md` plus `final_script.py` whose
   Critical Points are all checked. Found — show the path and reuse it
   unless the user asks to re-run. Otherwise go to *explore*.

4. **Explore.** Confirm on its own before driving the real site. If the
   user has not named the flow, ask. Load webwright's `SKILL.md` and run
   it to Done. Convert is the next step. Exploration stays in webwright.

5. **Repo — gitignore.** Propose `.gitignore` rules when unignored
   webwright artifacts exist (`outputs/`, `final_runs/`, screenshots/logs)
   or this run just scaffolded Playwright (`test-results/`,
   `playwright-report/`). Write only after confirmation. Add rules only;
   do not `git rm --cached` already-tracked files.

6. **Convert.** Take the qualifying run's `plan.md` and `final_script.py`
   and produce a standalone Playwright Test spec file. How to handle a
   scan hit is in [references/security.md](references/security.md).
   - **Scan input.** Run `scripts/scan-secrets.sh` on `final_script.py`.
     Non-zero exit: follow that doc. A visual read of the script is not
     a scan.
   - **Map and draft.** Map each Critical Point in `plan.md` one-to-one to an
     `expect()` assertion; that mapping is the whole of the conversion.
     Put credential values in `process.env`; leave selectors and
     non-credential fixtures as literals.
   - **Scan output.** Run `scripts/scan-secrets.sh` on the drafted spec
     before writing it. Non-zero exit: follow that doc. Write only a spec
     the script accepts.
   Place the spec in the project's existing e2e test directory (its
   Playwright config's `testDir`, or the project's established
   convention), named after the flow being converted.

7. **Validate.** Run all three gates, in order:
   - **Run** — execute the generated spec once; it passes.
   - **Stable** — re-run it 3 consecutive times; all 3 pass.
   - **Discoverable** — the project's test-run command finds the new spec
     file. A remote pipeline is not required.
   On failure, attempt an automatic fix and re-validate, up to 2 attempts.
   Still failing after that — stop and report. Hand back only a spec that
   has passed all three gates.

8. **Repo — CI.** After Validate, follow
   [references/ci.md](references/ci.md). Write only after confirmation.
