# Brief elements — detail

## Durability gate (step 1)

Ask before slicing whether the target surface is still in active use or about
to be replaced. Git history only suggests an answer — a file untouched since
2022 is consistent with both "abandoned" and "stable and correct" — it does
not decide, and the real answer often lives only in the user's head. Skipping
this once meant a 19-test batch got dispatched against a page whose capability
had already been split into a separate product with its own backend.

## Branch basing (step 4)

When a slice's allowed files overlap an unmerged slice's, base its branch on
that slice's branch instead of the default branch. Basing on default
guarantees a conflict in exactly the files the brief allows the new slice to
touch — the overlap step 1 already recorded is not hypothetical.

## Facts vs assumptions (step 5)

Name which claims in the brief you verified from source and which are your
own guesses for the implementer to check. Mixing them unmarked teaches the
implementer to distrust the whole brief, or — worse — to trust the wrong
part. A wrong assumption about infrastructure (assuming a data store needed
rebuilding when a script already re-seeded it on every run) cost one
implementer a wrong turn before it caught the mistake on its own.

## Defect-report shape (steps 5–6)

For a test-writing or audit slice, the defect report has a fixed shape: what
you did, what happened, what should have happened, the file:line responsible,
and whether the test asserts the current wrong behaviour or skips it. Report,
do not fix, unless the brief's scope says otherwise. Three real batches found
4, 8, and 4 defects respectively — this is the normal outcome of that kind of
slice, not an edge case.

A returned defect report never files a ticket by itself. Verify it — the
implementer's report may itself be a suspicion, not a confirmed defect, and
verifying can also reveal it is worse than flagged — then file only once the
user agrees. Filing on the report alone skips both checks.

## Slice-only resources (step 7)

A worktree and its branch are not the only things a slice can leave behind —
a brief that had the implementer spin up a container, seed a database, or
allocate any other resource scoped to that slice alone owes the same cleanup.
Shared infrastructure (a project-wide dev environment, a CI runner) is not
in scope here; only what the brief created for this slice specifically.
