# Verification setup

## Finding the entrypoint

Read, in order, and stop at the first that starts the whole stack:
`mise.toml` tasks, `package.json` scripts, `Makefile` targets,
`compose.yml` / `docker-compose.yml`, an existing `scripts/setup*`, then
the `README`'s run section. What comes out is one command, not a
narrative.

Where a setup script exists but prompts, wrap it rather than rewriting
it. Where only prose exists, condense the prose into a command; do not
relocate the prose.

## Non-interactive contract

The script this skill writes must satisfy all four:

- **Mode detection, layered**: an explicit `--non-interactive` flag,
  then `NON_INTERACTIVE=true|false`, then `CI=true`, then stdin not
  being a TTY.
- **Fail fast on a typo.** A `NON_INTERACTIVE` or `CI` value that is
  neither true nor false exits non-zero. Silently falling back to
  interactive mode leaves an agent hanging with no diagnosis.
- **Never prompt.** A step needing a human aborts with a message naming
  the prerequisite. It does not ask.
- **Prove it came up.** A health endpoint, a port accepting a
  connection, or a command exiting zero. A running container is not
  evidence.

A dependency's own log is often too quiet to show the request that
proves an integration. Raise its level for the check and restore the
repo's configuration afterwards, rather than concluding from silence.

## Human prerequisites

Installing tools, `mkcert -install` and friends, anything needing sudo,
obtaining credentials, setting CI secrets. These go into
`verification.md` as a checklist and into the script as fail-fast
checks.

**Test a credential for presence, never print it.** `[ -n "${VAR:-}" ]`
answers the only question a prerequisite check asks. A bare expansion,
an `echo`, or a `set -x` around one puts the value in the transcript,
and a transcript is not a place a secret can be taken back from — the
remedy is rotation, paid by whoever owns the credential. This applies to
every `.env` line, not only the ones that look secret. When the `wizard` skill is installed, suggest the developer use
it to turn the checklist into an interactive script — it exists for
exactly this and explicitly should not be driven by an agent. Do not
generate or run that script here.

## Ports, with several agents at once

Two strategies, chosen by how the project is reached.

**Reached by port** — derive a fixed offset from the worktree path, and
parameterise the compose ports minimally as `${SERVICE_PORT:-8080}`,
keeping the current value as the default so unset behaviour is
unchanged. Write the resolved ports to a runtime file the agent reads,
so nothing has to guess where the app is listening.

**Reached by hostname or TLS** — offsetting the port breaks the URL, so
this does not apply. Fall back to a lockfile mutex and record in
`verification.md` that only one agent runs the environment at a time.

## Mocks

Opt-in, and scaffold only. Add the service, an empty mapping directory,
and a documented way to add a scenario. Stop there.

Real stubs encode business rules — which identifier is matched, which
account gets the non-empty response — that cannot be derived from client
code. A generated stub passes while asserting nothing, which is worse
than no mock at all. Suggest filing a ticket to implement them.

Pick the tool by probing what the project already uses. Otherwise
propose by protocol: HTTP takes WireMock, Mockoon, or msw; LDAP takes an
openldap container; a database takes the real database in a container
rather than a mock.

## A remote test environment

Record three things and no more: how to reach it, where credentials come
from — the vault or variable name, never the value — and whether the
agent may deploy to it. That flag defaults to no.

Deploying to a shared environment affects other people's work, and an
agent's judgement about whether now is a safe moment is not reliable.
Opening it up should be a deliberate act by the developer, not a
checkbox during setup.

Evidence captured from such an environment carries two extra
requirements, because it is shared and its data may be real:

- **Cite the source**: the pipeline or deployment id and the commit SHA.
  Without them the evidence cannot be tied to this change rather than to
  someone else's deploy.
- **Assume PII is present** unless the environment is known to hold only
  test data. Mask, crop, or use a dedicated test account.

## Recording what could not be verified

An explicit section, not a silent omission. Each entry names the path
that went unverified and why — missing credentials, a service this repo
does not run, a device that is not available. A document that quietly
claims full coverage is worse than one that admits a gap.
