---
name: backfill-unit-tests
description: >-
  Use when backfilling unit test coverage on an existing, under-tested
  codebase — detecting the project's test framework across any language,
  generating tests for coverage gaps, and validating that they build, run
  under CI, and actually fail on broken code. For interactive feature-first
  development, use the tdd skill instead. Out of scope: integration,
  end-to-end, browser, and performance tests.
---

# Backfill Unit Tests

Detects an existing codebase's test framework at run time and backfills unit
test coverage for gaps, validating every generated test before handing it
back. This skill starts after code already exists and is under-tested; for
red-green development of new code, use the
[`tdd`](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md)
skill instead.

## Scope

**Unit tests only:** isolate the code under test, avoid real external
dependencies (network calls, open ports, timing-dependent assertions).
Integration, end-to-end, browser, and performance tests are out of scope —
don't generate them here even if asked; point the user to a skill for that
test type instead.

## Workflow

1. **Explore.** Read the target repo's manifests, config, existing tests,
   and README to determine its language, test framework, and the exact
   commands to build and run tests. Don't assume a framework from a fixed
   list — every language and project varies.

2. **Check test infrastructure exists.** If no test framework/runner is
   configured at all, stop and report this to the user. Don't install a
   framework or scaffold config yourself — that's a dependency decision the
   user makes, not this skill.

3. **Decide scope.** If the requested work fits within a single module or a single PR's
   worth of change, generate directly. Otherwise, first write out a plan —
   which files/functions will get coverage — and get the user's explicit
   confirmation before generating anything.

4. **Find the gaps.** If the user gave an explicit coverage target (e.g.
   "get this module to 80%") and the project already has a coverage tool
   configured, read its existing report to find what's uncovered. Otherwise,
   identify untested public functions/modules directly. Don't install or
   configure coverage tooling that isn't already present.

5. **Generate.** Write tests for the identified gaps, following
   [`references/good-tests.md`](references/good-tests.md). Two exceptions
   per gap:
   - **No seam to test through** — the code is too tightly coupled, depends
     on global state, or has no injection point. Skip it; don't refactor the
     implementation to add a seam, that's a separate decision for the user.
   - **Generating the test reveals a bug**, not a gap — the actual behavior
     doesn't match what a reasonable test would expect. Skip it; don't fix it
     here. A test-backfill diff that quietly changes behavior hides a bug fix
     inside what should be pure test coverage.

   Both exceptions are skip-and-report-by-default guardrails, not absolute bans: if
   the user's request explicitly asked for bug fixes or refactoring as part
   of this task, do them — otherwise skip means skip. Report every skip —
   which gap, and whether it was untestable or a suspected bug — alongside
   the generated tests when the task finishes.

6. **Validate.** Run all three gates, in order:
   - **Build** — the full workspace builds/compiles, not just the new test
     file in isolation.
   - **Discoverable** — the project's actual test-run command finds and
     executes the new tests.
   - **Mutation-lite** — break a small piece of the corresponding
     implementation, confirm the new test fails, restore it, confirm the
     test passes again. Catches tests that pass no matter what the code
     does.

7. **On failure**, attempt an automatic fix and re-validate, up to 2 attempts.
   Still failing after that — stop and report the failure and its likely
   cause. Don't loop indefinitely, and don't hand back a test that hasn't
   passed all three gates.
