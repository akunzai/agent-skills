---
name: pr-workflow
description: Use when preparing, creating, updating, or reviewing pull requests — enforcing pre-PR checks, atomic commits, dependency release links, and issue linkage (GitHub primary, non-GitHub referenced).
---

# PR Workflow

Standard operating procedure for preparing, opening, and managing Pull Requests (PR) and Merge Requests (MR). Default to GitHub (`gh` CLI); for other platforms, see [platform-tools.md](references/platform-tools.md).

## Preflight

- **Base Sync**: Before creating a feature branch or starting a new task, fetch and sync the default base branch (`git fetch origin && git checkout main && git pull --ff-only` or branch directly off `origin/main`).
- **Clean Working Tree**: Verify `git status` is clean before editing or opening PRs.
- **Verification**: Run local **tests** and **linters** before opening or updating PRs.

For bounded, context-heavy local checks, prefer an available named `check-runner`
and pass only commands selected by the primary agent. Require its exact command,
exit code, summary blocks, omitted-line count, and artifact reference.

### Worker routing

On Cursor CLI, keep `check-runner` work in primary, since Cursor gives it unrestricted tools; the read-only cheap-dev-workers roles stay enforced there.

Request the cheapest capable model and lowest sufficient effort (`low` for
routine); unsupported overrides inherit parent/configured defaults. Report
requested/actual only from runtime metadata, else inherited/unknown.

If a named role is unavailable/unsupported or returns an explicit
pre-execution dispatch/runtime error (for example capacity, rate limit,
rejected model, or launch error), try one generic fallback that preserves
the named worker's tools and permissions:

- **Check:** selected commands, artifacts allowed, no tracked/Git-state mutation;
  report command, exit, summaries, omissions, and artifact.
- **Log:** exact approved local artifact only; reject unsafe input; report causes
  and events without fetching runs.

Otherwise use primary; a generic pre-execution failure also falls back to
primary. Once a worker begins its assigned workload, its rejection or failure
is final: no other worker, primary rerun, stronger model, or higher effort.
If a dispatch error does not reveal whether execution began, stop that
dispatch and report the ambiguity; do not retry or duplicate that workload.

## Branching & Guardrails

- **Branch Guard**: Stay on feature branches; never push or merge directly into the default base branch without explicit approval.
- **Base Discovery**: Detect the base branch dynamically from repo evidence (`origin/HEAD`, PR target).
- **Fork Safety**: Confirm with user before opening PRs on upstream or third-party forks.
- **Stacked PRs**: Prefer native stacks over hand-set feature-branch bases —
  GitHub `gh stack` (public preview; official
  [`github/gh-stack` skill](https://github.com/github/gh-stack)), GitLab
  `glab stack` (experimental; bundled `glab-stack` skill). Hand-stacked: merge
  bottom-up, retargeting each PR onto the default branch first — closing
  keywords only fire there.

## Commit Hygiene

- **Atomic Commits**: Keep commits single-concern. Include release/changelog URLs on single dependency bumps.
- **Non-interactive**: Pass `GIT_EDITOR=true` or `--no-edit` on git rebase/commit/merge to bypass GUI editor prompts.

## Issue Linking

- **Auto-close**: Reserve `Closes #N`, `Fixes #N`, or `Resolves #N` solely for PRs that auto-close the issue on merge.
- **Part-of**: Use `Part of #N` or `See #N` for epic tracking and multi-PR tasks. GitHub matches those tokens even inside negation — never write `Closes #N` (or Fix/Resolve) next to an issue you must not close.
- **No Tracked Issue**: When a PR has no tracked issue, drop the Related Issue section entirely — never leave an unlinked `Closes #` or empty issue marker in the PR body.

## PR Lifecycle (GitHub Primary)

For GitLab, Gitea, Azure DevOps, or Bitbucket, see [platform-tools.md](references/platform-tools.md).

For a caller-selected remote failure log, classify and scope the source before
delegation. The primary downloads only that log to a local artifact; the worker
never fetches remote logs or discovers unrelated runs. Low-risk build, lint,
and test artifacts may go to a named `log-summarizer` after caller review.
Potentially sensitive logs require a sanitized artifact and residual-secret
gate first; otherwise keep them in primary.
Use the worker-routing fallback above when the named summarizer is unavailable
or unsupported.

Before writing the request body, read the repo's `docs/agents/pull-request.md`
(or equivalent: `docs/agents/merge-request.md`, native `.github` / GitLab
templates) and follow its description shape and visual table, keying the
visual to the user-visible change — a CLI or UI output change wins over an
internal flowchart even when one exists. Where the table asks for a
before/after pair, show both states, not just the after.

### Create PR
```bash
gh pr create --title "<type>(<scope>): <summary>" --body "<description>"
```

### Update PR (Amend / Force-push)
```bash
gh pr edit <pr_number> --title "<updated_title>" --body "<updated_body>"
```

**Guard body rewrites**: fetch, edit, and write back a PR/MR/issue body in one `set -euo pipefail` block; never write an empty or shrunken body (`test -s`) — see [body-rewrite.md](references/body-rewrite.md).
