---
name: gitlab-epic
description: Use ONLY when a git repository is hosted on GitLab to create, structure, or link GitLab epics, sub-issues, and issue relations.
---

# GitLab Epic & Issue Relations

Manage multi-issue epics, parent-child hierarchies, and issue relationships on GitLab repositories.

## Preflight & Hosting Check

Verify GitLab hosting (`git remote get-url origin`). For custom domains needing self-hosted GitLab detection, see [hosting-detection.md](references/hosting-detection.md).

## Tier Strategies

### Strategy A: Premium / Ultimate (Native Wiring)

Use native epics and issue links via `glab` CLI or REST API:

#### 1. Group Epics
```bash
glab api groups/:group_id/epics
```

#### 2. Link Sub-issue
```bash
glab api --method POST groups/:group_id/epics/:epic_iid/issues/:issue_id
```

#### 3. Blocked-by Links
```bash
glab api --method POST projects/:id/issues/:issue_iid/links \
  -f target_project_id=<target_project> \
  -f target_issue_iid=<target_iid> \
  -f link_type=blocks  # Options: relates_to, blocks, is_blocked_by
```

---

### Strategy B: Free / CE Tier (Label & Markdown Emulation)

Emulate epics using **markdown checklists** and **scoped labels**.

#### 1. Markdown Checklists
Tracking issue description:
```markdown
# Epic: User Authentication Redesign

## Sub-tasks
- [ ] #101 Core OAuth2 client refactor
- [ ] #102 JWT validation middleware
```
Child issue descriptions: `Part of #100` / `Relates to #105`.
Do not write `Closes`/`Fixes`/`Resolves` next to a tracking issue
even to say not to close it — GitLab still treats that as a closer.

#### 2. Scoped Labels (`key::value`)
- `type::epic`: Tracking issue.
- `epic::<epic-name>`: Tag child issues (e.g. `epic::user-auth`).
- `parent::<issue_id>`: Explicit parent tag (e.g. `parent::100`).

```bash
glab issue create --title "OAuth2 Client" --label "epic::user-auth,parent::100"
```
