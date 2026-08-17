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
and pass only commands selected by the primary agent. If dispatch is unavailable
or fails to launch, run them in primary without probing worker configuration.
Once launched, a check-runner failure is the task result; do not rerun it merely
because it failed. Require its exact command, exit code, summary blocks,
omitted-line count, and artifact reference.

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

## PR Lifecycle (GitHub Primary)

For GitLab, Gitea, Azure DevOps, or Bitbucket, see [platform-tools.md](references/platform-tools.md).

For a caller-selected remote failure log, classify and scope the source before
delegation. The primary downloads only that log to a local artifact; the worker
never fetches remote logs or discovers unrelated runs. Low-risk build, lint,
and test artifacts may go to a named `log-summarizer` after caller review.
Potentially sensitive logs require a sanitized artifact and residual-secret
gate first; otherwise keep them in primary.
If summarizer dispatch is unavailable or fails to launch, summarize in primary.
Once launched, its rejection or failure is the task result; do not rerun the
same summarization merely because it failed.

### Create PR
```bash
gh pr create --title "<type>(<scope>): <summary>" --body "<description>"
```

### Update PR (Amend / Force-push)
```bash
gh pr edit <pr_number> --title "<updated_title>" --body "<updated_body>"
```
