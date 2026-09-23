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
internal flowchart even when one exists.

### Create PR
```bash
gh pr create --title "<type>(<scope>): <summary>" --body "<description>"
```

### Update PR (Amend / Force-push)
```bash
gh pr edit <pr_number> --title "<updated_title>" --body "<updated_body>"
```

**Read-modify-write a body only behind a guard.** Editing part of an existing
body (a PR, MR, or the tracking issue whose table lists them) means fetch,
change, write back. If the fetch or the edit fails and the write still runs,
the forge stores an empty or truncated body, and GitLab CE keeps no version
to restore it from. Run all three under `set -euo pipefail` in one block
rather than an `&&` chain: a newline after a heredoc ends the chain, so the
write on the next line runs even though the fetch failed. Refuse to write a
file that is empty or shorter than the fetched body:

```bash
set -euo pipefail
gh pr view <pr_number> --json body -q .body > body.md
test -s body.md
cp body.md body.orig.md
# ...edit body.md...
test "$(wc -c < body.md)" -ge "$(wc -c < body.orig.md)" || { echo "body shrank; not writing" >&2; exit 1; }
gh pr edit <pr_number> --body-file body.md
```

Keep `body.orig.md` until the write is confirmed; it is the only copy. On
Windows, parse forge JSON from bytes (`sys.stdin.buffer`), not a text stream
the console codepage decodes. Drop the size check only when the edit is
meant to delete content, and then diff the two files before writing.
