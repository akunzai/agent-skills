<!-- Template. Replace every <angle placeholder> and every inline
     `placeholder` span; delete lines that do not apply. -->
<!-- Write the file in English, whatever <language> turns out to be: a
     document about issues is not an issue. <language> is the English name
     of a language, substituted into a sentence, never an instruction to
     translate what surrounds it. Write that name in English too: the first
     non-English word in the file is what pulls the rest of it across. -->

# Issue tracker: <GitHub | GitLab | other>

**This file is English throughout**, sample blocks included, so it reads
one way to every model, whatever language the repo chose for its issues.

Issues live as `placeholder:forge` issues. Use the `<gh | glab>` CLI for all
operations; it infers the repo when run inside a clone.

<!-- When issues live outside this repo's code forge, in another tool the
     developer named — replace the heading's forge name with that tool's,
     and every `<gh | glab>` command below with the CLI or MCP calls the
     developer already has configured for it. Keep each verb
     (create, view, list, comment, label, close) even when the mechanism
     changes, so an agent reading this recognizes the operation. Do not
     invent commands for a tool with no CLI or MCP configured yet: name
     the gap instead and point at `find-skills` or `skills-manager` to
     locate or install one. -->

Write issue titles and descriptions in **<language>**.

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
   a UI bug, a Mermaid diagram for a flow or state problem. In a Mermaid
   label, write a path parameter as `:id`, not `{id}`, and break lines
   with `<br/>`, not `\n`. Skip formats
   the description editor cannot render, such as a link to an external
   artifact or a raw HTML or SVG file. Upload it with the repeatable `--attach` flag
   (`<gh issue create --attach './bug.png#The error state' | glab issue create --attach ./bug.png>`);
   alt text follows the path after `#`. Only when capture is genuinely
   impossible, leave `<!-- screenshot pending: <what it should show> -->`
   rather than omitting it silently.
3. Close with a collapsed technical section, so it does not push the
   human summary below the fold:

```markdown
<details>
<summary>Technical details</summary>

<everything an implementer needs — for example, suspected cause, related
code paths, repro commands, log excerpts>

</details>
```

<!-- Keep the line below even when the visual guidance above is cut
short. It is the one rule whose absence costs someone else. -->
**No personally identifiable information in any attachment**; use test
data, masking, or cropping.

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

<how to prove it works, per `docs/agents/verification.md`; say here when
this needs a deployed environment rather than a local run>

<details>
<summary>Technical details</summary>

<only background — for example, related code paths, prior art, log
excerpts, open questions>

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
first page reads as absent. Do not write a label count into this file
either: the count a CLI prints is the page it fetched, a total copied out
of it reads as authoritative so nobody re-derives it, and it is wrong from
the next label onward. Nothing here invents a vocabulary; when a
label really is missing, that is a conversation with the maintainer, not
a label to create.

Check the other documents under `docs/agents/` before listing. Where one
already owns part of this vocabulary — `triage-labels.md` owns the triage
roles — point at it and list only what it does not cover. A label named in
both places has two owners and one of them goes stale on the next rename.

- **Required on every issue**: `placeholder:labels, or "none"`
- **Applied when it applies**: `placeholder:labels and what each one means`

## Epic issues

<!-- Delete this whole section when nothing here rolls up into a body of
     work tracked as a unit. Keep it when it does: an agent told to "open
     an epic" otherwise reaches for whichever mechanism its skill assumes,
     and on a forge that has no epics that means a command that fails. -->

`placeholder:forge` <has native epics | has no native epics>, so the
aggregating item here is `placeholder:what plays that role`.

<!-- GitLab Free/CE has no epics at all: they are Premium and group-level,
     and the API answers 403 or 404. GitHub has sub-issues rather than
     epics. On either, the shape that works is an ordinary issue that
     aggregates others, labelled so it can be found, with the children
     linked by the forge's own relation — `relates_to` through
     `glab api projects/:id/issues/:iid/links` on GitLab, sub-issues on
     GitHub. Name the label here and let the labels document own what it
     means, so it has one owner. -->

An epic aggregates related issues and is the single source of truth for a
body of work, rather than something an implementer picks up directly.

**When an epic records numbers** — test counts, coverage, burn-down — say
in the epic itself where each number comes from and when a new row may be
added: the source command or pipeline, and the point in time it is valid.
Without that the next agent fills the next row from whatever it has to
hand, the rows stop being comparable, and the table loses the only reason
it exists.

## When a skill says "publish to the issue tracker"

Create a `placeholder:forge` issue.

## When a skill says "fetch the relevant ticket"

Run `<gh | glab> issue view <number> --comments`.
