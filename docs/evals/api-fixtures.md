# API response-level fixtures

API skill evaluations keep the natural-language task, selected skill, and
response rubric as separate inputs. A fixture lives under
`evals/fixtures/api/<skill>/<case>/` and contains:

- `fixture.json`: pinned identity, input paths, treatment/control mapping,
  deterministic check IDs, and bounded artifact policy;
- `task.txt`: the same ordinary user task sent to both conditions;
- `rubric.json`: fixed response-level checks that can be evaluated without
  claiming native filesystem, process, permission, workspace, or tool state.

Rubric checks target the normalized `response_text` field. The fixture contract
requires checks for response structure, minimum references to supplied context,
and forbidden invention patterns, but leaves the actual headings, terms, and
patterns to each skill's rubric.

The treatment receives the selected skill from the manifest. The control must
use the same task and rubric with an explicit `null` skill input. A task must
not use slash invocation or harness-specific activation.

`fixture.json` pins separate revisions and SHA-256 values for the task, skill,
and rubric. Its deterministic check IDs must resolve to checks in the rubric.
Artifact policy is part of the fixture contract: result fields are allowlisted,
provider/session material is forbidden, and both field and artifact sizes are
bounded. A new skill adds another `<skill>/<case>` directory without changing
the runner or scoring semantics.

The current API paired runner consumes the task and skill paths and leaves
scoring to the later judge slice. The fixture and rubric are therefore
credential-free data and are safe to validate in ordinary pull-request CI.
