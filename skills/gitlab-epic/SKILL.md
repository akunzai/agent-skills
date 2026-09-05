---
name: gitlab-epic
description: Use ONLY when a git repository is hosted on GitLab to create, structure, or link GitLab epics, sub-issues, and issue relations.
---

# GitLab Epic & Issue Relations

Manage epics, parent-child hierarchies, and issue relationships on GitLab.

Focuses on epics, work items, and tier strategies. For general CLI syntax and gotchas, consult the official skill (`glab skills install --global`).

## Preflight & Tier Check

Verify GitLab hosting (`git remote get-url origin`; custom domains: [hosting-detection.md](references/hosting-detection.md)). Read tier:

```bash
glab api version                  # "enterprise": false => CE / Free
glab api groups/:group_id/epics   # 404 => no native epics
```

## Tier Strategies

### Strategy A: Premium / Ultimate (Native Wiring)

Native epics and issue links via `glab`:

```bash
# Group epics & child issue links
glab api groups/:group_id/epics
glab api --method POST groups/:group_id/epics/:epic_iid/issues/:issue_id

# Blocked-by links (options: relates_to, blocks, is_blocked_by)
glab api --method POST projects/:id/issues/:issue_iid/links \
  -f target_project_id=<target_project> -f target_issue_iid=<target_iid> -f link_type=blocks
```

---

### Strategy B: Free / CE Tier

Native epics are unavailable. Choose GraphQL work items or emulation:

- **Native Work Items (GraphQL)**: For real parent-child wiring on CE (Issue -> Task conversion, mutations, link constraints), see [work-items.md](references/work-items.md).
- **Emulation**: Use markdown checklists and scoped labels:

#### 1. Markdown Checklists
Tracking issue:
```markdown
# Epic: User Authentication Redesign
## Sub-tasks
- [ ] #101 Core OAuth2 client refactor
- [ ] #102 JWT validation middleware
```
Children: `Part of #100` / `Relates to #105`.
Never write `Closes`/`Fixes`/`Resolves` next to a tracking issue even in negation — GitLab still auto-closes.

#### 2. Scoped Labels (`key::value`)
On CE, `::` carries no native exclusivity, but conventions track hierarchy:
- `type::epic`: Tracking issue.
- `epic::<epic-name>`: Tag child issues (e.g. `epic::user-auth`).
- `parent::<issue_id>`: Explicit parent tag (e.g. `parent::100`).

```bash
glab issue create --title "OAuth2 Client" --label "epic::user-auth,parent::100"
```
