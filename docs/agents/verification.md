# Verification

How an agent exercises a change in this repo before it reaches review. Human
setup narrative lives in @CONTRIBUTING.md; this file holds only what an agent
needs.

## Running the gate

This repo ships skills, shell scripts, and plugin manifests. There is no stack
to start and no port to allocate, so the entrypoint is the project's own gate:

```sh
mise run lint
mise run test
```

<!-- drift:forge github -->
<!-- drift:entrypoint-cmd mise run lint -->
<!-- drift:entrypoint-cmd mise run test -->

Neither prompts. Both fail non-zero naming the offending file. A step needing a
human aborts rather than asking — see Human prerequisites below.

**Proof it ran**: both exit 0. `mise run test` prints one `PASS: tests/<name>.sh`
line per test script, so an empty run is visible rather than silently green.
`mise run lint-skills` prints the count of skills it checked.

## Checks

`mise tasks` lists every task with its own description; nothing is copied here.
What that lookup cannot give:

| What | Command |
| --- | --- |
| The full gate | `mise run lint` then `mise run test` |
| List the tasks and their descriptions | `mise tasks` |
| One test in isolation, while iterating | `bash tests/<name>.sh` |
| The AgentsView CLI contract (pulls a 42 MB pinned binary) | `mise run test-agentsview-contract` |
| Skill behaviour, live against Copilot | `mise run waza -- <suite>` |
| Only the suites touched vs `origin/main` | `mise run waza -- --changed` |
| SKILL.md token budget (3000, `.waza.yaml`) | `waza tokens compare origin/main --skills --threshold 10 --strict` |
| This document still matching the repo | `bash skills/setup-agent-ready-repo/scripts/check-drift.sh --run-entrypoint .` |

`mise run test` runs `tests/agentsview-cli-contract.sh` through the
`test-agentsview-contract` task, which supplies the CLI; running that one file
directly with `bash` fails for want of the binary.

## Skill behaviour

A change to a Waza-covered skill is verified locally. Run the suite for the
skill you touched, not the whole set:

```sh
mise run waza -- <skill>
```

It spends Copilot premium requests and takes roughly half a minute per task, so
it sits outside the gate above rather than inside it. Results land in
`waza-results/<skill>.json`, which is gitignored. Coverage, the pinned model per
suite, and the CI path mapping are in @docs/evals/waza.md.

`waza run --cache` skips a task whose spec, tasks, and fixtures are unchanged.
A cache hit is not evidence after a skill edit.

`.github/workflows/waza-eval.yml` runs the touched suites again on the pull
request. It is a backstop, not the primary instrument: quote your local run in
the description. Where Copilot quota is exhausted and the local run cannot
happen, say so and let the workflow be the evidence — a run that workflow
classified as skipped for quota or billing is not a pass either way.

### Dogfooding against a real agent

Waza measures one pinned model on a scripted task. It cannot show how the skill
reads to a live agent working this repo. Where this session runs inside Herdr,
drive that second reading yourself:

```sh
test "${HERDR_ENV:-}" = 1
```

When that passes, open a sibling pane in the caller's directory, start the agent
kind you want to observe — `claude`, `codex`, `copilot` and `gemini` are among
the supported kinds — and give it the task the skill is supposed to trigger on:

```sh
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start dogfood --kind codex --pane <pane-id-from-the-JSON-response>
herdr agent prompt dogfood "<the user-shaped request>" --wait --timeout 300000
herdr agent read dogfood --source recent-unwrapped --lines 200
```

The `herdr` skill is the authority on that CLI. Read every id out of the JSON
response rather than predicting it, keep `--no-focus` so the developer keeps
their pane, and close only panes you opened.

Two rules make the observation worth anything. **Name no skill in the prompt** —
a led agent proves only that it can follow instructions. **Report what it
misread** rather than whether it succeeded: the wording it skipped, the step it
invented, the trigger that never fired. That is the feedback a grader cannot
give, and it lands in the SKILL.md or as a widened case in the suite's own task
prompt.

Dogfooding is evidence about the skill's wording. It does not replace
`mise run waza -- <skill>`, and a clean dogfood run is not a passing suite.

## Human prerequisites

Run once, by a person. The gate fails until they are done.

- [ ] Install [mise](https://mise.jdx.dev/) and run `mise install` in the clone.
- [ ] `gh auth login`, for any issue or pull-request operation.
- [ ] `copilot login`, for `mise run waza`. In CI this is `GITHUB_TOKEN` plus
      the workflow permission `copilot-requests: write`.

The `wizard` skill turns a checklist like this into an interactive script. It is
for the developer to run, not an agent.

## Ports

Not applicable. This repo has no listening service, so several agents can run
the gate in the same clone at once. Tests that need isolation create their own
`mktemp -d` HOME and clean it up on exit — see @tests/to-memory-storage.sh.

There is no deployed environment, and no credential in this repo. Copilot and
`gh` read the developer's own login.

## Capturing evidence

- Terminal recording: the `tcut` skill. Absent it, paste the command and its
  output in a fenced block inside the description's `<details>` trailer.
- Website walkthrough: the `to-walkthrough-video` skill.

**This document is where the capture rules live**, and @docs/agents/pull-request.md
points here rather than restating them. A capture taken on the developer's own
machine carries their account's data, username, and home paths as readily as a
shared environment does. Assert on the frame, a marker, or fixture data, and
crop or mask what the tool happened to be showing. Never print a credential to
check it; `[ -n "${VAR:-}" ]` answers the only question a prerequisite asks.

## Not verified

- `mise run render-roles`: writes `plugins/cheap-dev-workers` artifacts, so it
  is not part of the read-only gate. Run it deliberately when `roles/` changes.

<!-- drift:file mise.toml -->
<!-- drift:file .waza.yaml -->
<!-- drift:file .github/workflows/waza-eval.yml -->
