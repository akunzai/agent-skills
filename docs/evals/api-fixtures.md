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
minimum per-item grounded findings, and forbidden invention patterns, but leaves the
actual headings, terms, components, and patterns to each skill's rubric. Static
validation rejects check kinds or targets that assert native filesystem,
process, permission, workspace, tool, or transcript state, and bounds artifact
field and total sizes. Each `forbid_regex` check also declares regression
phrases so its patterns are exercised without hard-coding a skill-specific test.

The treatment receives the selected skill from the manifest. The control must
use the same task and rubric with an explicit `null` skill input. A task must
not use slash invocation or harness-specific activation.

`fixture.json` pins separate revisions and SHA-256 values for the task, skill,
and rubric. Its deterministic check IDs must resolve to checks in the rubric.
Artifact policy is part of the fixture contract: result fields are allowlisted,
provider/session material is forbidden, and both field and artifact sizes are
bounded (the current fixture uses 4 KiB fields and a 256 KiB artifact, sufficient
for the default 15 pairs). A new
skill adds another `<skill>/<case>` directory without changing the runner or
scoring semantics.

The API paired runner consumes the task, skill, and rubric paths. It evaluates
deterministic response checks separately, fully resamples treatment and control
for every configured replicate, sends one anonymized candidate at a time to the
fixed judge model, and records only bounded scores/evidence and metadata. Each
pair carries a one-based `replicate_index`; the result records the configured
`replicate_count`. Candidate and judge phases also record the fixed retry
ceiling, whether it was exhausted, and a bounded list of typed attempt outcomes;
raw provider responses remain forbidden. Per-model lift distributions preserve
every scored or not-scored sample, while median/min/max/sign consistency use
only scored lifts and remain null when none exist. The fixture and rubric are
credential-free data and are safe to validate in ordinary pull-request CI.
