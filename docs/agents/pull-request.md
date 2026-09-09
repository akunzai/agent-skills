# Pull requests

Write PR titles, descriptions, and comments in **English**. **Git commit
messages are English**, imperative, subject under 72 characters — they live in
history and get searched by tooling. This file itself stays English throughout,
sample blocks included.

This repo's `.github/pull_request_template.md` is authoritative on structure.
What follows only adds what it does not say. Its checklist line "Tests pass
(`npm test` or equivalent)" resolves here to `mise run test` and `mise run lint`
— see @docs/agents/verification.md.

## Preparing

- Work on a feature branch. Never prepare a request from the default branch.
- Prefix the title with a Conventional Commit type and the skill or plugin as
  the scope, matching this repo's merged history: `feat(to-walkthrough-video): …`,
  `fix(setup-agent-ready-repo): …`, `docs(agents-md): …`, `ci(waza): …`,
  `refactor(plugins): …`. A change spanning the repo drops the scope (`docs: …`).
- Link the issue in the template's Related Issue section (`Closes #<n>`).
- **Do not open a request, draft included, without the developer asking.**

## Description shape

1. A plain-language opening: what changed and why, as a reviewer who did not
   write it would need it.
2. A visual the forge renders inline, chosen by what changed:

   | Change | Visual |
   | --- | --- |
   | Flow or state transition | Mermaid `flowchart` / `stateDiagram` |
   | Cross-service or API interaction | Mermaid `sequenceDiagram` |
   | Data model | Mermaid `erDiagram` |
   | Appearance | Before/after screenshots |
   | Multi-step interaction | Short recording |
   | Shell script or skill prose only | None; test output instead |

   Pair before and after. At most one diagram unless it is such a pair. No
   personally identifiable information in any attachment — @docs/agents/verification.md
   holds the capture rules.

   Upload the file with the repeatable `--attach` flag —
   `gh pr create --attach './after.png#After'`, and the same flag on
   `gh pr edit|comment`. Alt text follows the path after `#`, and a path the
   body already references as `![alt](./after.png)` is rewritten to point at
   the uploaded asset. Only when capture is genuinely impossible, leave a named
   placeholder comment such as `<!-- recording pending: hook firing on Stop -->`.
3. A collapsed technical trailer holding affected paths, implementation notes,
   the verification commands you ran, and log excerpts.

## Commits

- Atomic: one concern per commit. A skill edit and an unrelated CI fix are two
  commits, not one.
- The subject uses the same Conventional Commit type and scope as the title.
- `tidy-commits` cleans WIP noise before the request is opened.

## Tests land with the behaviour

- **Product logic**: `skills/*/scripts/`, `plugins/*/scripts/`, `scripts/`,
  `evals/*.sh`. A change here lands in the same request with a test under
  `tests/` that actually runs the script and asserts its exit code and output,
  registered in `.github/workflows/tests.yml`.
- **Skill prose** (`skills/*/SKILL.md`): structure is checked by
  `mise run lint-skills`; behaviour is a Waza suite under `evals/<skill>/`.
  Do not add grep-the-SKILL.md phrase locks. New coverage widens an existing
  suite's own task prompt rather than adding a second task — see
  @docs/evals/waza.md for why.
- **Exempt**: `README.md`, `docs/`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/`,
  and dependency bumps with no behaviour change.
- **Structurally untestable** code is declared in the description, naming what
  covers it instead.

No coverage threshold. The reviewer judges whether the new behaviour is
actually exercised.

## Version bumps ship the change

Claude Code pins marketplace plugins on the `version` string, so a shipped file
that changes without a bump never reaches an installed user. Any change under
`skills/` bumps the root `.claude-plugin/plugin.json`; any change under
`plugins/<name>/` bumps that plugin's `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`, kept equal. `tests/plugin-version-bump.sh` enforces
both, so the gate catches a miss. Semver rules are in @CONTRIBUTING.md.

A new or renamed skill also updates `README.md` and the `skills` array in
`.claude-plugin/plugin.json`; `tests/skill-catalog-sync.sh` enforces that.

## Review readiness

Nothing unverified enters review. Two orders satisfy that:

- **Default**: run the gate locally per @docs/agents/verification.md, then open
  the request with the evidence.
- **A Waza-covered skill**: also run that skill's suite locally
  (`mise run waza -- <skill>`) and quote the result. The PR workflow runs it
  again as a backstop.
- **When Copilot quota is exhausted** and the local suite cannot run, open the
  request as a draft (`gh pr create --draft`), let
  `.github/workflows/waza-eval.yml` run, attach evidence citing the run id and
  the commit SHA, then mark it ready. A run the workflow classified as skipped
  for quota or billing is not a pass; say so.

State in the description which paths were verified and which were not, with the
reason.
