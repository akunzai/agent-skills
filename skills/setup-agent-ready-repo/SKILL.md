---
name: setup-agent-ready-repo
description: >-
  Set up a repository so agents can file tickets, open pull or merge
  requests, and verify their own changes.
disable-model-invocation: true
metadata:
  capabilities: shell, network, edits-agent-instructions, runs-repo-commands
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
then a backtick path — never `@path` or a Markdown link; the `agents-md`
skill says why.

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
place: replace `<angle placeholder>` and `placeholder` marks, delete
what does not apply, leave every `drift:` HTML comment, and leave the
template's own sentences alone: `--check` matches their wording.

`--check` scans the installed documents for a placeholder nobody
replaced, for any guarantee in
[guarantees.tsv](references/guarantees.tsv) the document no longer
carries, and for `@path` file references in any `docs/agents/*.md`. Run
it before asking for confirmation. On any finding, fix the file and rerun
until it exits 0; do not judge whether the finding applies.

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

A CLI that is absent, or logged out of the host, is not evidence about
the forge. Whenever the remote suggests GitLab, step 2 included, check
the CLI, its login and the project skill:
[gitlab-cli.md](references/gitlab-cli.md). Otherwise say which forge the
remote suggests and ask.

## Phase 1 — filing and review conventions

Ask one language question: which language issues and PR/MR bodies use.
Everything else is fixed and is not asked. Commit messages are English,
because they live in history and get searched by tooling. Each rule is
written into the document it governs; no language table goes into
`AGENTS.md`.

The same answer picks the capture locale: when the UI ships the language
issues and PR/MR bodies use (`locales/`, i18n), `verification.md` records
its code, such as `zh-TW` for Traditional Chinese, not the `en-US` browser
default.

What you add to a document may be in that language, English, or a mix.
Where a forge-native template already dictates structure, that template
wins.

Then propose rather than interview. Probe and offer a concrete default
the developer confirms or edits: the source paths whose changes must
land with tests, which of the repo's existing labels an agent should
apply, the request-title convention, and where issues are tracked.

Where issues are tracked, the probes behind those defaults, a forge-native
request template the repo already has, body shape, diagrams, evidence and
PII rules: [ticket-and-pr.md](references/ticket-and-pr.md).

**Done when** the issue document and the PR/MR document exist, each
carries its language rule, `install-templates.sh --check` exits 0 against
them, and the developer has confirmed both.

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
it to turn that checklist into an interactive script; this pass never
runs one. Built on request, it walks only the human steps and finishes on
the entrypoint's own check, so people and agents share one check.

Then run it. Three outcomes. It comes up; or its entrypoint needs a TTY,
and the non-TTY readiness subcommand the project ships counts as coming
up; or neither is possible — missing credentials, a dependency this repo
does not run — and it goes under the document's unverified section with
the reason, rather than claiming a pass.

Entrypoint detection, port strategy, local and deployed verification,
and what an existing `README`, `CONTRIBUTING.md` or `AGENTS.md` command
list leaves for this document to hold:
[verification.md](references/verification.md). Capture tooling per
platform, the UI locale to capture in, and capture rules an existing
document already states: [capture.md](references/capture.md).

**Done when** `verification.md` exists, carries its `drift:` markers and a
`UI locale:` line (the language requests are written in when the UI ships
it, else the UI default), the entrypoint has run clean or
its failure is recorded as a named gap, and `AGENTS.md` carries the
pointers. Where `AGENTS.md` does not exist, hand that off to the
`agents-md` skill. Where it is not installed, write a minimal `AGENTS.md`
holding a one-line project description and the three pointers, and say
in the hand-back that `agents-md` should audit it.

## Phase 3 — optional

Offer each on its own confirmation: **mocks** for a dependency that
cannot run locally, **a remote test environment**, **port allocation**
when several agents work the repo at once, and **a forge-native template
skeleton**. Scope, tool choice and the credential rule for the first
three: [verification.md](references/verification.md); for the skeleton:
[ticket-and-pr.md](references/ticket-and-pr.md).

**Done when** each offer has been accepted or declined on the record.

## Re-running

On a repo an earlier pass already set up — which phase to resume, the two
drift checks to run before asking anything, upgrading a repo an earlier
version of this skill wrote, and migrating `@path` pointers:
[re-running.md](references/re-running.md).

## Related

`agents-md` for `AGENTS.md` itself. `pr-workflow`, `github-epic`,
`gitlab-epic` at runtime. `record-walkthrough` and `tcut` for capture.
`wizard` for the human prerequisite script.
