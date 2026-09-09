# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all
operations; it infers the repo from `git remote -v` when run inside a clone.

Write issue titles and descriptions in **English**. This file itself stays
English throughout, sample blocks included, so it reads one way to every model.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Title: a concise descriptive phrase. This repo's merged history prefixes issue
titles with the same Conventional Commit type the eventual commit will use
(`feat(<skill>): …`, `fix(<skill>): …`, `spec: …`, `docs(<skill>): …`), so keep
that shape when the issue already names its target skill.

## Description shape

1. Open with what a maintainer or a new contributor would observe: the symptom
   or the request, in plain language. Skip file paths and function names unless
   the reader cannot otherwise locate the issue.
2. Add a visual the forge renders inline — a Mermaid diagram for a flow or a
   decision tree, a terminal recording for a CLI or hook behaviour. Skip formats
   the description editor cannot render, such as a link to an external artifact
   or a raw HTML or SVG file. Attachments must not contain personally
   identifiable information; use test data, masking, or cropping. Upload with the
   repeatable `--attach` flag (`gh issue create --attach './bug.png#The error state'`);
   alt text follows the path after `#`. Only when capture is genuinely impossible,
   leave `<!-- screenshot pending: <what it should show> -->` rather than omitting
   it silently.
3. Close with a collapsed technical section, so it does not push the human
   summary below the fold:

```markdown
<details>
<summary>Technical details</summary>

suspected cause, related code paths, repro commands, log excerpts

</details>
```

## Spec issues

An issue an agent will implement from carries a different shape, because its
reader is building rather than triaging. Acceptance criteria stay above the
fold; only background goes into `<details>`.

```markdown
<one paragraph: the observable outcome>

## Acceptance criteria

- [ ] <checkable statement about observable behaviour>
- [ ] <one per criterion; a reviewer can tick these without reading code>

## Scope

- In: <paths or areas>
- Out: <what this issue deliberately does not change>

## Verification

<how to prove it works, per docs/agents/verification.md; say here when a
Waza suite under evals/<skill>/ is the only thing that can cover it>

<details>
<summary>Technical details</summary>

related code paths, prior art, log excerpts, open questions

</details>
```

An issue with unanswered open questions is not ready to implement. Say so in
the issue rather than letting an agent guess.

## Labels

This repo's own labels, read from `gh label list --limit 100`. The CLI defaults
to 30 and reports that page as the whole set, so a label past the first page
reads as absent. Nothing here invents a vocabulary; when a label really is
missing, that is a conversation with the maintainer, not a label to create.

- **Required on every issue**: none.
- **Applied when it applies**: `bug`, `enhancement`, `documentation`,
  `question`, `duplicate`, `invalid`, `wontfix`, `help wanted`,
  `good first issue`, `ready-for-agent` (fully specified for an AFK agent),
  `dependencies` and `github_actions` (applied by Dependabot, not by hand).

Triage roles map to these strings in @docs/agents/triage-labels.md.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me` — the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
