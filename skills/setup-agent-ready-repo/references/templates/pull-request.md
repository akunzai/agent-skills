<!-- Template. Name the file pull-request.md on GitHub, merge-request.md on GitLab. -->
<!-- Replace every <angle placeholder>; delete lines that do not apply. -->
<!-- Write the file in English, whatever <language> turns out to be: a document
     about requests is not a request. <language> is a name you substitute into
     a sentence, never an instruction to translate what surrounds it. -->

# <Pull | Merge> requests

**This file is English throughout**, sample blocks included, whatever
language the repo chose for its requests.

Write <PR | MR> titles, descriptions, and comments in **<language>**.
**Git commit messages are English**, imperative, subject under 72
characters — they live in history and get searched by tooling.

<!-- If the repo has a native template, say so and stop duplicating it:
This repo's `<.github/PULL_REQUEST_TEMPLATE.md | .gitlab/merge_request_templates/X.md>`
is authoritative on structure. What follows only adds what it does not say. -->

## Preparing

- Work on a feature branch. Never prepare a request from the default branch.
- <Use a concise descriptive title with no Conventional Commit prefix,
  because one request may carry more than one kind of change. | Prefix the
  title with a Conventional Commit type, matching this repo's merged
  history.> Delete the alternative that does not apply.
- **Do not open a request, draft included, without the developer asking.**

## Description shape

1. A plain-language opening: what changed and why, as a reviewer who did
   not write it would need it.
2. A visual the forge renders inline, chosen by what changed:

   | Change | Visual |
   | --- | --- |
   | Flow or state transition | Mermaid `flowchart` / `stateDiagram` |
   | Cross-service or API interaction | Mermaid `sequenceDiagram` |
   | Data model | Mermaid `erDiagram` |
   | Appearance | Before/after screenshots |
   | Multi-step interaction | Short recording |
   | Backend or library only | None; test output instead |

   Pair before and after. At most one diagram unless it is such a pair.

   Upload the file with the repeatable `--attach` flag —
   `<gh pr create --attach './after.png#After' | glab mr create --attach ./after.png>`.
   Alt text follows the path after `#`, and a path the body already
   references as `![alt](./after.png)` is rewritten to point at the
   uploaded asset. Only when capture is genuinely impossible, leave a
   named placeholder comment.
3. A collapsed technical trailer holding affected paths, implementation
   notes, verification commands, and log excerpts.

<!-- Keep the line below even when the visual guidance above is cut
short. It is the one rule whose absence costs someone else. -->
**No personally identifiable information in any attachment**, whatever
you end up attaching. `verification.md`'s capture rules say what that
means here.

## Tests land with the behaviour

- **Product logic**: `<paths>`. A change here lands with its tests in the
  same request.
- **Exempt**: `<paths>` — documentation, CI configuration, scripts, and
  dependency bumps with no behaviour change.
- **Structurally untestable** code — configuration classes, all-static
  factories — is declared in the description, naming what covers it instead.

No coverage threshold. The reviewer judges whether the new behaviour is
actually exercised.

## Review readiness

Nothing unverified enters review. Two orders satisfy that:

- **Default**: verify locally per `verification.md`, then open the
  request with the evidence.
- **When only a deployed environment can verify** — see the list in
  `verification.md` — open the request as a draft
  (`<gh pr create --draft | glab mr create --draft>`), let the pipeline
  deploy, verify against it, attach evidence citing the pipeline or
  deployment id and the commit SHA, then mark it ready.

State in the description which paths were verified and which were not,
with the reason.
