---
name: gitlab-epic
description: Use ONLY when a git repository is hosted on GitLab to create, structure, or link GitLab epics, sub-issues, and issue relations.
---

# GitLab Epic & Issue Relations

Manage multi-issue epics, parent-child hierarchies, and issue relationships on GitLab repositories.

## Preflight & Hosting Check

Verify GitLab hosting (`git remote get-url origin`). For custom domains needing self-hosted GitLab detection, see [hosting-detection.md](references/hosting-detection.md).

Then read the tier and the hierarchy rules off the instance:

```bash
glab api version                  # "enterprise": false => CE / Free
glab api groups/:group_id/epics   # 404 => no native epics
```

Ask which children each type accepts rather than trusting the web UI - an
issue that shows a "Child items" section may only accept tasks:

```bash
glab api graphql -f query='
query { project(fullPath: "GROUP/PROJECT") { workItemTypes { nodes {
  name
  widgetDefinitions { type
    ... on WorkItemWidgetDefinitionHierarchy {
      allowedChildTypes { nodes { name } } } } } } } }'
```

On GitLab CE 19.x this answers `Issue -> [Task]`: an issue cannot be the
parent of another issue, even though the UI shows a "Child items" section on
it. Either convert the child to an accepted type (see below) or fall back to
Strategy B.

`glab api graphql` answers a `__type` introspection query with a full schema
dump instead. Save that dump and read the type out of it rather than
re-querying.

## Native Parent-Child (GraphQL only)

`glab` has no parent/child command: `glab issue create --epic` targets
Premium group epics, and `glab work-items create|update` (EXPERIMENTAL)
exposes no parent flag. Setting a parent is a GraphQL mutation.

```bash
# Resolve global IDs first: project(fullPath:).workItems(iids: ["100","101"])
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<child>",
    hierarchyWidget: { parentId: "gid://gitlab/WorkItem/<parent>" }
  }) { errors workItem { iid } }
}'
```

`workItemUpdate` reports refusals in `errors` with `"data": {...}` and HTTP
200, so check that field - a failed mutation does not look like a failed
request. `workItemHierarchyAddChildrenItems` does the same job from the
parent's side.

To make a child of a type the parent will not accept, convert it first.
`WorkItemUpdateInput` carries no type field; conversion is its own mutation:

```bash
glab api graphql -f query='
mutation {
  workItemConvert(input: {
    id: "gid://gitlab/WorkItem/<child>",
    workItemTypeId: "gid://gitlab/WorkItems::Type/<type>"  # from workItemTypes
  }) { errors workItem { iid workItemType { name } } }
}'
```

Converting an issue to a task keeps its iid, description, labels and state,
and it still appears in `glab issue list` and `GET projects/:id/issues` (as
`"type": "TASK"`). Two things it costs:

- A task does not appear on issue boards. On a team that runs its workflow
  through board columns, that is the whole tracking surface.
- A task cannot itself have children, so convert leaves of the tree, not
  intermediate nodes.

Put both to the user and let them choose between real hierarchy and
Strategy B - never convert an existing issue silently. `workItemConvert`
reverses it if they change their mind.

An item already joined by an issue link cannot then be made a child of the
same item: the mutation answers `cannot assign a linked work item as a
parent`. Choose one relationship. To convert, delete the link first
(`glab api --method DELETE projects/:id/issues/:iid/links/:issue_link_id`,
id from `GET .../links`), then set the parent.

## Tier Strategies

### Strategy A: Premium / Ultimate (Native Wiring)

Use native epics and issue links via `glab` CLI or REST API (for parent-child
within allowed types, see Native Parent-Child above):

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

Scoped labels are Premium. On CE they are ordinary labels whose names happen
to contain `::` - they carry no mutual exclusivity - so prefer a label the
project already uses (`tracking`) over inventing a `key::value` vocabulary
nobody enforces.

- `type::epic`: Tracking issue.
- `epic::<epic-name>`: Tag child issues (e.g. `epic::user-auth`).
- `parent::<issue_id>`: Explicit parent tag (e.g. `parent::100`).

```bash
glab issue create --title "OAuth2 Client" --label "epic::user-auth,parent::100"
```
