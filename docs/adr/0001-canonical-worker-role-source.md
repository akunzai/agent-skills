# 1. Canonical Worker Role source with committed derived artifacts

Date: 2026-09-01

## Status

Accepted

## Context

`cheap-dev-workers` ships four Worker Roles in two native formats: Claude and
Copilot CLI load `agents/*.md` (YAML frontmatter plus Markdown, permissions as
`tools:`), Codex CLI loads `codex-agents/*.toml` (permissions as
`sandbox_mode`). Eight files, hand-maintained, expressing one set of rules.

They had already drifted. The same Git-mutation boundary was worded four
different ways across the roles, and the Codex descriptions had quietly lost
the cost-routing sentence the Claude descriptions carry. The existing test
defended against this with roughly sixty phrase greps — locks that assert a
string appears in two files, which cannot distinguish a deliberate runtime
difference from an accident, and which break on any wording cleanup.

Some differences are legitimate. Claude plugin subagents cannot spawn another
subagent, so a Claude role relays through the primary while a Codex role may
take one nested hop. Forcing the two runtimes onto lowest-common-denominator
wording would make both worse.

## Decision

`roles/` is the single authority. `scripts/render-roles.sh` projects it onto
all eight native artifacts, and those artifacts stay committed to Git.

- `roles/shared.role` carries semantics only — each invariant's id, the roles
  it applies to, and a `class` of `shared`, `runtime`, or `drift`. It renders
  no bytes, because shared *prose* is very nearly an empty set at the byte
  level today.
- `roles/<role>.role` carries per-runtime prose plus one `capability`, from
  which the adapter derives both `tools:` and `sandbox_mode`.
- The grammar is line-oriented with no quoting, escaping, or continuation.
  Anything it cannot represent verbatim is rejected with a `file:line` error.
- `--check` is read-only and fails on any mismatch; `--write` validates
  everything before it moves anything.

The first migration was behaviour-neutral: all eight artifacts are reproduced
byte for byte, and the pre-existing content test passed unchanged.

## Consequences

The permission invariant is now structural rather than asserted: one
`capability` produces both native permission fields, so a read-only role cannot
become writable in one runtime alone. The cross-runtime phrase locks are
redundant and get deleted; the remaining locks are on stable ids and on the
native seams, which survive a wording cleanup instead of breaking on it.

The divergent wording is not fixed — it is made visible. Four wordings of one
invariant now sit under one id, which is the backlog for a later normalization
pass. That pass is deliberately blocked: collapsing them changes the prompt
text that reaches the model, and nothing in this repository currently observes
an actual dispatch, permission enforcement, or model selection. Verifying that
needs an installed plugin and runtime event metadata, which is a separate
integration seam.

### The cost we chose to pay

The artifacts carry **no generated-by header**. A header would change the
prompt bytes the model receives, and these files are prompts, not code. The
consequence is real: `agents/check-runner.md` looks hand-written, and a
contributor who edits it gets a CI failure with no explanation inside the file
they touched.

Three things compensate, none of them inside the artifact:

1. `plugins/cheap-dev-workers/AGENTS.md` states the ownership rule.
2. `.gitattributes` marks the artifacts `linguist-generated=true`, so GitHub
   collapses them by default. They are deliberately **not** marked `-diff`:
   these are prompts, and a reviewer must be able to see wording change.
3. The `--check` failure names the source file to edit instead.

We accepted this over the alternatives: build-time generation without
committing is not possible because the runtimes and installers read fixed paths
and the repository has no packaging build, and continuing to hand-maintain
eight files is what produced the drift in the first place.
