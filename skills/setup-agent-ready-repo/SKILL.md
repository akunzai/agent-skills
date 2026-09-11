---
name: setup-agent-ready-repo
description: >-
  Set up a repository so agents can file tickets, open pull or merge
  requests, and verify their own changes.
disable-model-invocation: true
---

# Set up an agent-ready repo

A one-time setup pass. It writes the repo's agent-facing conventions for
filing work, shaping a pull or merge request, and verifying a change
before it reaches review. Then it stops. Running the conventions is the
job of `pr-workflow`, `github-epic`, `gitlab-epic`, and the capture
skills, not of this one.

Everything it produces is a durable write to someone's repository, so
**nothing lands without an explicit confirmation**. Show the exact
content, name the path, wait. This gate is the real safety mechanism:
the frontmatter above stops implicit invocation in Claude Code and
Codex, but GitHub Copilot CLI has no per-skill control and may still
reach this skill on its own.

Probe rather than assume, and stay self-contained. Sibling skills named
here are optional depth, never a prerequisite; when one is absent,
degrade to written steps and say so in the file you write.

## What it writes

Into the target repo, all at the root even in a monorepo, because forge
conventions and language are repo-wide. A package that verifies
differently gets a section, not a second file.

| Path | Holds |
| --- | --- |
| `docs/agents/issue-tracker.md` | Forge, CLI, issue body shape, labels |
| `docs/agents/pull-request.md` or `merge-request.md` | PR/MR body shape, commits, tests, review readiness |
| `docs/agents/verification.md` | Non-interactive entrypoint, evidence, gaps |
| `AGENTS.md` | One read-trigger line per document |
| a non-interactive entrypoint | One command an agent can run; a script only where none exists |

The pointers go under `AGENTS.md`'s existing Pointers section, one line
each. Repo wording may vary; the shape may not: occasion, then `read`,
then a backtick path. `@path` expands every turn on Copilot CLI and
Claude Code and is inert on VS Code Copilot Chat and opencode. Markdown
links in `AGENTS.md` can auto-include on VS Code. Neither belongs here.

```markdown
- When filing or triaging an issue, read `docs/agents/issue-tracker.md`
- When opening a pull or merge request, read `docs/agents/pull-request.md`
- Before running or reporting verification, read `docs/agents/verification.md`
```

On GitLab the request line names `docs/agents/merge-request.md` instead.
Do not write a nested `AGENTS.md` under `docs/agents/` or at a package
boundary for these documents. They are repo-wide; the root trigger
lines are how they are found.

Run [install-templates.sh](scripts/install-templates.sh) `--forge
<github|gitlab|none>` rather than composing the files. It places
[issue-tracker.md](references/templates/issue-tracker.md),
[pull-request.md](references/templates/pull-request.md) and
[verification.md](references/templates/verification.md) under
`docs/agents/`, skipping any that already exist, and keeps the `drift:`
markers `--check` and `check-drift.sh` read. Then edit the copies in
place: replace every `<angle placeholder>`, delete what does not apply,
leave every `drift:` HTML comment, and leave the English prose alone.
Writing a document from a template regenerates it, and regeneration
follows the conversation's language; copying bytes does not.

`--check` scans the installed documents for stray CJK, for a placeholder
nobody replaced, and for any guarantee in
[guarantees.tsv](references/guarantees.tsv) the document no longer
carries. Run it before asking for confirmation, and fix what it names.

A repo set up by an earlier version reaches the current one through that
last check. It reports the guarantee and where in the template to read
the original, never a diff: the installed document holds this repo's own
labels, paths and gate commands, and those edits are the reason it is
worth keeping. Adapt the template's wording to what the document already
says, one guarantee at a time, each on its own confirmation.

Link to what a `README` or `CONTRIBUTING.md` already says, and keep only
what is agent-specific. Where `AGENTS.md` already lists build and test
commands, `verification.md` becomes their single source and the
`AGENTS.md` entry shrinks to the pointer. Same rule when the repo already has
`.github/PULL_REQUEST_TEMPLATE.md` or `.gitlab/merge_request_templates/`:
the native template stays authoritative on structure and the document
says so. Generating a native template is opt-in and produces a skeleton
only.

## Forge ladder

Start from `git remote get-url origin`, then confirm against the host's
own API rather than against the domain string, so a self-hosted install
lands correctly. Both probes below resolve the host from that remote.

1. `gh repo view --json name` succeeds — GitHub or GHES. Write
   `pull-request.md`.
2. `glab repo view` succeeds — GitLab, any tier. Write
   `merge-request.md`. `glab api version` is not repo-scoped: it
   succeeds in a GitHub clone.
3. A remote, but neither probe — another forge. Write the generic issue
   profile and ask which CLI the repo uses.
4. No remote — skip both ticket documents and their pointers.
   `verification.md` alone is still worth writing.

A CLI that is absent is not evidence about the forge. When neither is
installed, say which one the remote suggests and ask.

## Phase 1 — filing and review conventions

Ask one language question: which language issues and PR/MR bodies use.
Everything else is fixed and is not asked. Commit messages are English,
because they live in history and get searched by tooling. Each rule is
written into the document it governs; no language table goes into
`AGENTS.md`.

**The documents you write are English throughout** — headings, prose,
and the placeholder text inside a sample block alike. They are read by
models, and one language means one reading. The answer names the
language an agent later types into the forge; it never changes the
language of the file that records the rule. `pull-request.md` is a
document about pull requests, not a pull request, so "requests are in
<language>" leaves the file English and puts `<language>` inside the
sentence the file states. Translating the document is the failure to
avoid here, and it looks like obedience while you do it.

The exception is a **literal**: a string reproduced character for
character, such as a label that lands in a published release note, or a
citation of an existing section title that a reader has to match. Show a
literal as it must appear, and write everything the agent reads rather
than copies in English. Where a forge-native template already dictates
structure, that template wins; nothing else does.

Then propose rather than interview. Probe and offer a concrete default
the developer confirms or edits: the source paths whose changes must
land with tests, which of the repo's existing labels an agent should
apply, and the request-title convention, read from merged requests
(`gh pr list --state merged --limit 30 --json title`,
`glab mr list --merged`). Read the labels with the page size raised
(`gh label list --limit 100`, `glab label list --per-page 100`): both
default to 30 and present that page as the whole set, so a label further
down reads as missing. Inventing a label vocabulary, or importing one
from another project, produces labels nobody uses; a missing label is a
conversation with the maintainer.

Body shape, diagram selection, evidence and PII rules:
[ticket-and-pr.md](references/ticket-and-pr.md).

**Done when** the issue document and the PR/MR document exist, each
carries its language rule, and the developer has confirmed both.

## Phase 2 — verification

The deliverable is one recorded, repeatable command that runs without a
TTY, plus a check proving it worked.
Wrap what the project already has, and record an unrunnable dependency
as a gap. Generating a compose file or inventing a mock produces
plausible, wrong configuration, which is the failure this skill exists
to prevent.

Where the project already has one non-interactive command, record that
command; a wrapper is a second source of truth that drifts. A library,
CLI, or TUI has no stack to start and no port to allocate: record its
gate command plus a check that the built artifact runs, and delete the
Ports and deployed sections.

Human-only prerequisites — installing tools, trusting a certificate,
anything needing sudo, obtaining credentials — go into the document as a
checklist. The entrypoint exits non-zero naming them; it never
prompts. When the `wizard` skill is installed, suggest the developer use
it to turn that checklist into an interactive script. Do not produce or
run one here.

Then run it. Three outcomes. It comes up; or its entrypoint needs a TTY,
and the non-TTY readiness subcommand the project ships counts as coming
up; or neither is possible — missing credentials, a dependency this repo
does not run — and it goes under the document's unverified section with
the reason, rather than claiming a pass.

Then sweep for references to the section you shrank, source comments
included.

Entrypoint detection, port strategy, local and deployed verification:
[verification.md](references/verification.md). Capture tooling per
platform: [capture.md](references/capture.md).

**Done when** `verification.md` exists and carries its `drift:` markers,
the entrypoint has run clean or
its failure is recorded as a named gap,
and `AGENTS.md` carries the pointers. Where `AGENTS.md` does not exist, hand that off to the
`agents-md` skill, which owns the quality bar and the `CLAUDE.md`
symlink. Where that skill is not installed, write a minimal `AGENTS.md`
holding a one-line project description and the three pointers, and say
in the hand-back that `agents-md` should audit it.

## Phase 3 — optional

Offer each of these on its own confirmation.

- **Mocks** for a dependency that cannot run locally. Scaffold only: the
  service, an empty mapping directory, and a documented way to add a
  scenario. Stubs encode business rules that cannot be inferred from
  client code, so suggest filing a ticket to implement them.
- **A remote test environment**, recorded as reachability plus where
  credentials come from — never the credentials. The "agent may deploy"
  flag defaults to no and is the developer's to flip.
- **Port allocation** when several agents work the repo at once.
- **A forge-native template skeleton.**

**Done when** each offer has been accepted or declined on the record.

## Re-running

Resume at the first incomplete phase; do not re-ask what a document
already answers. Present is not complete: a document another skill wrote
counts as this skill's only if it carries the Phase 1 language rule.

[check-drift.sh](scripts/check-drift.sh) compares four mechanical facts:
documented forge against the remote, the entrypoint still resolving and
running (`drift:entrypoint` for a script path, `drift:entrypoint-cmd` for
a task-runner command), documented ports against the compose file, and
files the document depends on still being present. It reads them from
`drift:` HTML-comment markers that `verification.md` carries, so the
document stays the single source and the markers stay invisible when
rendered. Write those markers whenever you write the file.

[install-templates.sh](scripts/install-templates.sh) `--check` answers the
other half: which guarantees the current templates pin that these
documents no longer carry. Run both on a re-run, before asking anything.

If `AGENTS.md` still has `@docs/agents/<doc>.md` lines, propose the
read-trigger shape above and wait. `--check` does not parse `AGENTS.md`.

Report drift and stop. Fixing it needs the same confirmation as writing
it did.

The four are what a script can decide. Semantic drift — whether a mock
still covers a new field — is left to review.

## Related

`agents-md` for `AGENTS.md` itself. `pr-workflow`, `github-epic`,
`gitlab-epic` at runtime. `to-walkthrough-video` and `tcut` for capture.
`wizard` for the human prerequisite script.
