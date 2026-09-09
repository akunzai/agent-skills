# Ticket and request conventions

What goes into `issue-tracker.md` and into `pull-request.md` /
`merge-request.md`. Use the forge's own vocabulary throughout: pull
request and `gh` on GitHub, merge request and `glab` on GitLab.

## Body shape

Issues and requests share one shape, top to bottom:

1. **A plain-language opening.** What a product manager or a new
   engineer would observe: the symptom, or the request. No file paths,
   function names, or line numbers unless the reader cannot otherwise
   find the thing.
2. **A visual, inline.** Only formats the forge renders in the
   description itself. A link to an external artifact and a raw HTML or
   SVG file both fail this test.
3. **A collapsed technical trailer.** Everything an implementer needs —
   suspected cause, code paths, repro commands, log excerpts — inside
   `<details><summary>` so it does not push the human summary below the
   fold.

## Two kinds of issue

The shape above serves a **report or request**: a human reads it and
decides what to do. An issue an **agent implements from** inverts the
priority, so it gets its own shape in
[templates/issue-tracker.md](templates/issue-tracker.md): acceptance
criteria, scope in and out, and how to verify all sit above the fold,
and `<details>` holds only background.

Putting acceptance criteria in the collapsed section is the failure to
avoid. It is the one part the implementer must read, and the one part a
skim will miss.

## Choosing the visual

The table is in [templates/pull-request.md](templates/pull-request.md),
which ships into the repo and has to stand alone there. Apply it to the
issue document too. It keys the visual to what changed rather than to
what is easy to capture, caps a ticket at one diagram unless it is a
before-and-after pair, and pairs before with after so a reviewer
compares rather than infers.

## Evidence rules

- **No personally identifiable information** in any attachment. Use test
  data, masking, or cropping. This is not a judgement call about whether
  a field looks sensitive.
- **Local capture identifies as much as a shared environment does.** A
  terminal or desktop capture on the developer's own machine carries
  their account's real data, their username, and their home paths, and a
  CLI or TUI is normally captured exactly that way. Assert on the frame,
  a marker, or fixture data rather than on whatever the tool happened to
  be showing.
- **Attach the file from the CLI.** Both forges upload local media and
  embed it in the body through a repeatable `--attach` flag:
  `gh pr create --attach './after.png#Tree after'`, and the same flag on
  `gh pr edit|comment` and `gh issue create|edit|comment`;
  `glab mr create --attach ./after.png` on GitLab, where the flag is
  still marked experimental. Alt text follows the path after `#`. A path
  the body already references as `![alt](./after.png)` is rewritten in
  place to point at the uploaded asset. `gh`'s flag does not cover
  GitHub Enterprise Server, and it needs push access to the repository,
  so a fork-based contributor still falls back to the placeholder below. Confirm it against the installed binary's
  `--help` rather than from memory: it is recent, and an agent that
  assumes attachment is impossible falls back to a placeholder for a
  visual it could have uploaded.
- **When capture is genuinely impossible, leave a named placeholder**
  rather than omitting the visual silently, so the gap is visible in review:
  `<!-- screenshot pending: before -->`,
  `<!-- screenshot pending: after -->`,
  `<!-- recording pending: <what it should show> -->`.
- Recordings go in as the forge's own inline player where one exists.
  Scope the recording to the flow, not to a whole test run, and stay
  under the forge's attachment cap.

## Commit messages

English, imperative, subject under 72 characters, regardless of the
language chosen for tickets. They live in history and get searched by
tooling. State this in the request document, next to the commit rules,
so it is where an agent about to commit will read it.

## Tests landing with behaviour

Express it as paths, never as "add tests" — the vague form reliably
decays into nothing.

- **Product logic paths**: the source directories whose changes must
  land with their tests in the same request. Propose these from the repo
  layout; the developer edits.
- **Exempt paths**: documentation, Markdown, CI configuration, scripts,
  and dependency bumps with no behaviour change.
- **The escape hatch**: for code that is structurally untestable —
  configuration classes, all-static factories — say so in the
  description and name what covers it instead.

No coverage threshold. A reviewer judges whether the new behaviour is
actually exercised, not whether a number moved.

## Review readiness

Two orders, one invariant: **nothing unverified enters review.**

- **Local verification**, the default. Verify, then open the request
  with the evidence.
- **Deployed verification**, where only an environment CI deploys can
  exercise the change. Open the request as a draft
  (`gh pr create --draft`, `glab mr create --draft`), let the pipeline
  deploy, verify against it, attach the evidence, and only then mark it
  ready for review.

Which order applies is decided per change, from the paths it touches.
`verification.md` lists the areas that need deployed verification. Most
repos are mixed, so this is a per-change call rather than a project-wide
flag.

Open a request, draft included, only when the developer asks for one.
