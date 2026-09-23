# Verification strategy

An upgrade promises **behaviour parity**: the same inputs produce the same
outputs on the old and the new target. Tests are the evidence, so the
upgrade is only as safe as the tests that run on both targets.

## Assess: grade the verification gap

Record each of these with evidence (file, job, count), not an impression:

- **Test coupling.** Which tests reach code only through a component the
  upgrade replaces (the IoC container, an ORM session context, a
  serializer). A suite coupled to Spring.NET or `HttpContext` fails for
  infrastructure reasons after the swap and masks real regressions.
- **Test kind.** Pure unit tests versus tests needing a live database,
  cache, or external service. A suite with no fakes or substitutes cannot
  run on a CI image that lacks those services.
- **Host coverage.** Which web hosts, APIs, and consoles have any test that
  starts them: bootstrapping, configuration binding, DI registration,
  middleware order. Framework-to-modern breaks these first.
- **Smoke and health.** Whether one command proves each host starts and
  serves an authenticated request, and whether a health endpoint exists.
- **End-to-end.** Which user flows run in a browser, and what triggers them
  in CI. A job gated on changes to its own spec files never runs on a
  product change.
- **Coverage signal.** Whether coverage is collected on every change, and
  which assemblies its filter leaves out.

## Decide: the verification strategy

Put these to the user with the other Decide options:

- **Characterization tests first.** Before a behaviour-touching task
  changes code, pin today's behaviour (odd behaviour included) in tests
  that run unchanged on both targets. The same test passing on both is the
  parity proof.
- **Test seam.** New tests reach code without the component being
  upgraded: a plain DI container, an in-process database (SQLite), and
  substitutes or fakes for external services. Tests that must use the old
  container say why.
- **Smoke.** One command starts the hosts, waits for health, runs a small
  tagged browser or HTTP suite, and prints output a reviewer can paste into
  the request. Local smoke is the minimum bar; a post-deploy run against a
  shared environment backs it up without loading the CI runners.
- **End-to-end.** The browser tool and the main flows, weighted towards the
  areas the upgrade touches (auth, uploads, scheduling, caching).
- **Performance parity.** A load script (k6 or similar) run against old and
  new builds in the same environment on the same data, with a threshold
  such as p95 within +10%, as a cutover gate.
- **Test data.** A small, reproducible, secret-free baseline for smoke and
  end-to-end runs; a large team snapshot suits manual development but
  drifts under assertions.
- **Scope split.** Backfilling tests across the whole product outlives the
  upgrade. Track it as its own effort, and make the upgrade's cutover
  depend only on the milestones it needs (test seam, smoke, main flows).

## Execute: gate by risk tier

Classify every task by runtime risk, not diff size, and require that
tier's evidence before merge:

| Tier | Example | Evidence |
| --- | --- | --- |
| Low | Project-file edits, unused references, docs | The build and test gate |
| Behaviour | Serialization format, a third-party major version, I/O paths, scheduling | Characterization tests on trunk or as the request's first commit; local smoke output; a staging check where the change needs one |
| Operational | An external dependency the code cannot show (a service still connecting to a cache being removed) | Written confirmation from the people who run it |
