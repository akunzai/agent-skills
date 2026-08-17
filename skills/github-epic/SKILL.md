---
name: github-epic
description: Use ONLY when a git repository is hosted on GitHub to create, structure, or link GitHub epics, sub-issues, and dependency relationships.
---

# GitHub Epic & Sub-issues

Manage multi-issue epics, parent-child task hierarchies, and blocking dependencies natively on GitHub.

## Preflight & Hosting Check

Verify GitHub hosting (`git remote get-url origin`). For custom domains needing self-hosted GHES detection, see [hosting-detection.md](references/hosting-detection.md).

## Native Wiring (GitHub API)

GitHub supports native sub-issue hierarchies and issue dependency links via `gh api` using numeric database IDs (not issue numbers).

### 1. Database ID Lookup
```bash
gh api repos/<owner>/<repo>/issues/<issue_number> --jq .id
```

### 2. Link Sub-issue to Epic
```bash
gh api --method POST repos/<owner>/<repo>/issues/<parent_number>/sub_issues \
  -F sub_issue_id=<child_db_id>
```

### 3. Link Blocked-by Dependency
```bash
gh api --method POST repos/<owner>/<repo>/issues/<child_number>/dependencies/blocked_by \
  -F issue_id=<blocker_db_id>
```

## Issue Linking Conventions

- **Auto-close**: Use `Closes #N`, `Fixes #N`, or `Resolves #N` solely when merging auto-closes issue `#N`.
- **Part-of**: Tag `Part of #N` or `See #N` for multi-PR epics. Never pair closing keywords with tracking issues. GitHub matches those tokens even inside negation — do not write `Closes #N` (or Fix/Resolve) next to a tracking issue to say not to close it.
- **Dual References**: Combine native API wiring with markdown prose links for cross-interface readability.
