# Re-running on a repo already set up

Resume at the first incomplete phase; do not re-ask what a document
already answers. Present is not complete: a document another skill wrote
counts as this skill's only if it carries the Phase 1 language rule.

Run both checks below before asking anything. Report drift and stop:
fixing it needs the same confirmation as writing it did.

## The two checks

[check-drift.sh](../scripts/check-drift.sh) compares four mechanical
facts: documented forge against the remote, the entrypoint still
resolving and running (`drift:entrypoint` for a script path,
`drift:entrypoint-cmd` for a task-runner command), documented ports
against the compose file, and files the document depends on still being
present. It reads them from `drift:` HTML-comment markers that
`verification.md` carries, so the document stays the single source and
the markers stay invisible when rendered. Write those markers whenever
you write the file.

[install-templates.sh](../scripts/install-templates.sh) `--check` answers
the other half: which guarantees the current templates pin that these
documents no longer carry, and whether any `docs/agents/*.md` still has
an `@path` file reference.

The four are what a script can decide. Semantic drift — whether a mock
still covers a new field — is left to review.

## A repo set up by an earlier version

It reaches the current one through `--check`. That check reports the
guarantee and where in the template to read the original, never a diff:
the installed document holds this repo's own labels, paths and gate
commands, and those edits are the reason it is worth keeping. Adapt the
template's wording to what the document already says, one guarantee at a
time, each on its own confirmation.

## `@path` pointers left by an older pass

If `AGENTS.md` still has `@docs/agents/<doc>.md` lines, or any
`docs/agents/*.md` still has an `@` file reference, propose backtick
paths (the read-trigger shape in `AGENTS.md`) and wait. `--check` flags
`@path` in `docs/agents/*.md`; it does not parse `AGENTS.md`.
`check-drift.sh` still compares only the four recorded facts.
