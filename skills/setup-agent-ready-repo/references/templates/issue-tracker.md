<!-- Template. Replace every <angle placeholder>; delete lines that do not apply. -->

# Issue tracker: <GitHub | GitLab | other>

Issues live as <forge> issues. Use the `<gh | glab>` CLI for all
operations; it infers the repo when run inside a clone.

Write issue titles and descriptions in **<language>**. This file itself
stays English throughout, sample blocks included, so it reads one way to
every model.

## Conventions

- **Create**: `<gh issue create --title "..." --body "..." | glab issue create --title "..." --description "..."`. Use a heredoc for multi-line bodies.
- **Read**: `<gh | glab> issue view <number> --comments`
- **List**: `<gh issue list --state open --json number,title,labels | glab issue list -F json>`
- **Comment**: `<gh issue comment <number> --body "..." | glab issue note <number> --message "...">`
- **Label**: `<gh issue edit <number> --add-label "..." | glab issue update <number> --label "...">`
- **Close**: `<gh | glab> issue close <number>`

Use a concise descriptive title with no Conventional Commit prefix.

## Description shape

1. Open with what a product manager or a new engineer would observe: the
   symptom or the request, in plain language. Skip file paths and
   function names unless the reader cannot otherwise locate the issue.
2. Add a visual the forge renders inline — a screenshot or recording for
   a UI bug, a Mermaid diagram for a flow or state problem. Skip formats
   the description editor cannot render, such as a link to an external
   artifact or a raw HTML or SVG file. Attachments must not contain
   personally identifiable information; use test data, masking, or
   cropping. When capture is impossible, leave
   `<!-- screenshot pending: <what it should show> -->` rather than
   omitting it silently.
3. Close with a collapsed technical section, so it does not push the
   human summary below the fold:

```markdown
<details>
<summary>Technical details</summary>

suspected cause, related code paths, repro commands, log excerpts

</details>
```

## Spec issues

An issue an agent will implement from carries a different shape, because
its reader is building rather than triaging. Acceptance criteria stay
above the fold; only background goes into `<details>`.

```markdown
<one paragraph: the observable outcome, in <language>>

## Acceptance criteria

- [ ] <checkable statement about observable behaviour>
- [ ] <one per criterion; a reviewer can tick these without reading code>

## Scope

- In: <paths or areas>
- Out: <what this issue deliberately does not change>

## Verification

<how to prove it works, per docs/agents/verification.md; say here when
this needs a deployed environment rather than a local run>

<details>
<summary>Technical details</summary>

related code paths, prior art, log excerpts, open questions

</details>
```

Use the vocabulary the project already defines for its domain, so the
issue, the tests, and the code name the same things.

An issue with unanswered open questions is not ready to implement. Say
so in the issue rather than letting an agent guess.

## Labels

This repo's own labels, read from
`<gh label list --limit 100 | glab label list --per-page 100>`. Both CLIs
default to 30 and report that page as the whole set, so a label past the
first page reads as absent. Nothing here invents a vocabulary; when a
label really is missing, that is a conversation with the maintainer, not
a label to create.

- **Required on every issue**: <labels, or "none">
- **Applied when it applies**: <labels and what each one means>

## When a skill says "publish to the issue tracker"

Create a <forge> issue.

## When a skill says "fetch the relevant ticket"

Run `<gh | glab> issue view <number> --comments`.
