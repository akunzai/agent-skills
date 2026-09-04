# GitLab Work Item Hierarchy (CE & GraphQL)

`glab` has no parent/child command: `glab issue create --epic` targets Premium group epics, and `glab work-items create|update` exposes no parent flag. Setting a parent is a GraphQL mutation.

## 1. Instance Hierarchy Capabilities

Ask which children each type accepts rather than trusting the web UI — an issue showing a "Child items" section may only accept tasks:

```bash
glab api graphql -f query='
query { project(fullPath: "GROUP/PROJECT") { workItemTypes { nodes {
  name
  widgetDefinitions { type
    ... on WorkItemWidgetDefinitionHierarchy {
      allowedChildTypes { nodes { name } } } } } } } }'
```

On GitLab CE 19.x this answers `Issue -> [Task]`: an issue cannot be the parent of another issue. Either convert the child to an accepted type or fall back to Strategy B emulation.

Note: `glab api graphql` answers a `__type` introspection query with a full schema dump. Save that dump and read the type out of it rather than re-querying.

## 2. Parent-Child Mutation

Resolve global IDs first via `project(fullPath:).workItems(iids: ["100", "101"])`:

```bash
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<child>",
    hierarchyWidget: { parentId: "gid://gitlab/WorkItem/<parent>" }
  }) { errors workItem { iid } }
}'
```

`workItemUpdate` reports refusals in `errors` with `"data": {...}` and HTTP 200 — check that field. `workItemHierarchyAddChildrenItems` performs the same operation from the parent's side.

## 3. Type Conversion (`workItemConvert`)

To make a child of a type the parent will not accept, convert it first. `WorkItemUpdateInput` carries no type field; conversion is its own mutation:

```bash
glab api graphql -f query='
mutation {
  workItemConvert(input: {
    id: "gid://gitlab/WorkItem/<child>",
    workItemTypeId: "gid://gitlab/WorkItems::Type/<type>"  # from workItemTypes
  }) { errors workItem { iid workItemType { name } } }
}'
```

Converting an issue to a task keeps its iid, description, labels, and state, and it still appears in `glab issue list` and `GET projects/:id/issues` (as `"type": "TASK"`). Three costs to confirm with the user first:

- **No issue boards**: A task does not appear on issue boards. If the team tracks work via board columns, conversion loses visibility.
- **No further nesting**: A task cannot itself have children. Convert leaves of the tree, not intermediate nodes.
- **No MR auto-close**: A closing pattern in a merge request description does not close a task. GitLab parses the reference but classifies it as `MENTIONED` rather than `CLOSES`, so the merge leaves the task open. Confirmed on CE 19.3.1 with `Closes #N`; the `/-/issues/N` and `/-/work_items/N` URL forms the docs prescribe for work items behave the same. Check the classification before relying on it — `closes_issues` reports nothing for a task at all, so read `linkType`:

  ```bash
  glab api graphql -f query='{ project(fullPath: "GROUP/PROJECT") { mergeRequest(iid: "<iid>") {
    linkedWorkItems { linkType workItem { iid state workItemType { name } } } } } }'
  ```

  The same trailer against an issue answers `CLOSES` on that instance, which is what makes this a type restriction rather than a syntax error. Upstream says otherwise — [#440851](https://gitlab.com/gitlab-org/gitlab/-/work_items/440851) shipped MR-to-task closing in 17.3 (Free) — but MR/work item persistence is still being reworked in [#601174](https://gitlab.com/gitlab-org/gitlab/-/issues/601174) (19.4), so re-test rather than assuming this holds on a newer instance. Expect to close converted tasks by hand.

Never convert an existing issue silently. Put all three tradeoffs to the user. `workItemConvert` reverses it if needed.

## 4. Issue Link Conflicts

An item already joined by an issue link cannot be made a child of that same item (`cannot assign a linked work item as a parent`).

To convert a linked relationship to parent-child:
1. Delete the existing link:
   ```bash
   glab api --method DELETE projects/:id/issues/:iid/links/:issue_link_id
   ```
   (Retrieve `:issue_link_id` via `GET projects/:id/issues/:iid/links`).
2. Run `workItemUpdate` to set the parent.
