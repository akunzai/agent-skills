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

## Branching & Guardrails

- **Branch Guard**: Stay on feature branches; never push or merge directly into the default base branch without explicit approval.
- **Base Discovery**: Detect the base branch dynamically from repo evidence (`origin/HEAD`, PR target).
- **Fork Safety**: Confirm with user before opening PRs on upstream or third-party forks.

## Commit Hygiene

- **Atomic Commits**: Keep commits single-concern. Include release/changelog URLs on single dependency bumps.
- **Non-interactive**: Pass `GIT_EDITOR=true` or `--no-edit` on git rebase/commit/merge to bypass GUI editor prompts.

## Issue Linking

- **Auto-close**: Reserve `Closes #N`, `Fixes #N`, or `Resolves #N` solely for PRs that auto-close the issue on merge.
- **Part-of**: Use `Part of #N` or `See #N` for epic tracking and multi-PR tasks.

## PR Lifecycle (GitHub Primary)

For GitLab, Gitea, Azure DevOps, or Bitbucket, see [platform-tools.md](references/platform-tools.md).

### Create PR
```bash
gh pr create --title "<type>(<scope>): <summary>" --body "<description>"
```

### Update PR (Amend / Force-push)
```bash
gh pr edit <pr_number> --title "<updated_title>" --body "<updated_body>"
```
