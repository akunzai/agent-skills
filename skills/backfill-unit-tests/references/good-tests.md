# Good Unit Tests

Test through public interfaces, not implementation details. A test that
breaks on refactor without any behavior change is coupled to
implementation — mocking internal collaborators, asserting on call
counts/order, or reaching into private state.

**No tautological assertions.** The expected value must come from an
independent source — a known-good literal, a worked example — never
recomputed the way the code computes it. `expect(add(a, b)).toBe(a + b)`
passes by construction and proves nothing; `expect(add(2, 3)).toBe(5)` does.
The mutation-lite gate in the main workflow exists to catch this class of
test if one slips through.

**Mock only at system boundaries** — external APIs, databases, time,
randomness, the filesystem. Never mock your own modules or anything you
control.
