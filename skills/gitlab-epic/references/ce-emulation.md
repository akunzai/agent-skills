# Emulating an Epic on CE / Free

No native epics and no group container, so an ordinary project issue plays the
epic. Call it the **epic issue** throughout.

## 1. Epic Issue + Issue Links

Label the epic issue `epic`. Its body holds the board (in-flight / next / done)
and the child list. Attach each child with `relates_to`, the one link type
every tier has. `glab` exposes no command surface for issue links — it is raw
`glab api` only:

```bash
glab api --method POST projects/:id/issues/:issue_iid/links \
  -f target_project_id=<target_project> -f target_issue_iid=<target_iid> -f link_type=relates_to
```

## 2. Markdown Checklists

```markdown
# Epic: User Authentication Redesign
## Sub-tasks
- [ ] #101 Core OAuth2 client refactor
- [ ] #102 JWT validation middleware
```

Point a child back with `Part of #100` or `Relates to #105`. GitLab auto-closes
on `Closes`/`Fixes`/`Resolves` anywhere in the body, negation included, so
those three words stay out of an epic issue entirely.

Short refs render here precisely because the epic issue is a project issue.
Write full URLs in anything that may later be promoted to a native epic, where
they stop resolving.

## 3. Scoped Labels (`key::value`)

On CE, `::` carries no native exclusivity, but conventions track hierarchy:

- `type::epic`: The epic issue.
- `epic::<epic-name>`: Tag child issues (e.g. `epic::user-auth`).
- `parent::<issue_id>`: Explicit parent tag (e.g. `parent::100`).

```bash
glab issue create --title "OAuth2 Client" --label "epic::user-auth,parent::100"
```

Audit the existing taxonomy first and narrow a near-duplicate rather than
adding a second name for one role. A pre-existing `tracking` label described as
"tracking issue or external dependency" conflates the aggregating role with the
waiting-on-something role; leave both in place and neither gets applied
consistently. `glab label list` pages at 30 and prints that page's count as
though it were the total ("Showing label 30 of 30"), so an existing label reads
as missing — pass `-P 100`.
