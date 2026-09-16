---
name: gitlab-epic
description: Use ONLY when a git repository is hosted on GitLab to create, structure, or link GitLab epics, sub-issues, and issue relations.
---

# GitLab Epic & Issue Relations

For general `glab` syntax and gotchas, consult the official skill (`glab skills install --global`).

## Preflight & Tier Check

Verify GitLab hosting (`git remote get-url origin`; custom domains: [hosting-detection.md](references/hosting-detection.md)). Epics are Premium/Ultimate and live on the **group**, not the project. Probe before emitting any epic command:

```bash
glab api version                             # "enterprise": false => CE / Free
glab api "groups/<group>"                    # 200 => the group path is right
glab api "groups/<group>/epics?per_page=1"   # 403 or 404 => no native epics
```

Probe the group first — a 404 from the epics endpoint is otherwise indistinguishable from a mistyped path. Either code means no native epics: CE 19.3.2 answers 404, 403 is a paid tier answering a token with project but no group access. Both take Strategy B.

Epics API: deprecated since 17.0, removed in API v5. On 18.1+ use the Work Items API ([work-items.md](references/work-items.md)).

## Tier Strategies

### Strategy A: Premium / Ultimate (Native Wiring)

```bash
# Group epics & child issue links
glab api groups/:group_id/epics
glab api --method POST groups/:group_id/epics/:epic_iid/issues/:issue_id

# Issue links. relates_to is Free-tier; blocks / is_blocked_by need Premium.
glab api --method POST projects/:id/issues/:issue_iid/links \
  -f target_project_id=<target_project> -f target_issue_iid=<target_iid> -f link_type=blocks
```

An epic or group work item has no project context: `#123` and `!456` render as literal text there. Write `group/project#123` or the full URL.

---

### Strategy B: Free / CE Tier

Choose:

- **Native Work Items (GraphQL)**: real parent-child wiring on CE (Issue -> Task conversion, mutations, link constraints) — [work-items.md](references/work-items.md).
- **Emulation**: an ordinary issue plays the epic, wired up with `relates_to` links, markdown
  checklists (`Part of #100`), and the scoped labels `type::epic`, `epic::<epic-name>`,
  `parent::<issue_id>` — [ce-emulation.md](references/ce-emulation.md) carries the commands and
  the taxonomy audit.

## Measurements

An epic that records numbers states in its own body where each came from and when a row may be added; otherwise the next agent fills the table from whatever is at hand and the rows stop being comparable.
