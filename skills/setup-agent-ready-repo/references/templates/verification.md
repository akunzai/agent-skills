<!-- Template. Replace every <angle placeholder>; delete sections that do not apply. -->

# Verification

How an agent exercises a change in this repo before it reaches review.
Human setup narrative lives in `<README.md | CONTRIBUTING.md>`; this file
holds only what an agent needs.

## Starting the environment

```sh
<the one non-interactive command>
```

<!-- drift:forge <github|gitlab|other|none> -->
<!-- drift:entrypoint <scripts/dev-up.sh> -->

It never prompts. A step needing a human aborts non-zero naming the
prerequisite — see Human prerequisites below.

**Proof it came up**: `<health endpoint, port check, or command>`.

Entry point: `<url>`. Test account: `<account>` / `<where the password comes from>`.

## Checks

| What | Command |
| --- | --- |
| <unit tests> | `<command>` |
| <lint> | `<command>` |
| <build> | `<command>` |

## Human prerequisites

Run once, by a person. The start command fails until they are done.

- [ ] <install tool>
- [ ] <trust certificate>
- [ ] <obtain credentials>

<!-- If the wizard skill is available, suggest turning this list into an
interactive script. Do not have an agent run that script. -->

## Ports

<!-- Reached by port: -->
Ports come from `<runtime file>`, derived from the worktree path so two
agents can run the stack at once. Compose reads `${<VAR>:-<default>}`.

<!-- drift:port <8080> -->

<!-- Reached by hostname or TLS: -->
This stack is reached by hostname, so ports cannot be offset. **Only one
agent runs the environment at a time**; the lock is `<path>`.

## Changes that need a deployed environment

These cannot be verified locally. Open the request as a draft, let the
pipeline deploy, then verify against `<environment url>`:

- <area>: <why local cannot cover it>

Evidence from that environment cites the pipeline or deployment id and
the commit SHA, and is treated as containing real data: mask, crop, or
use a dedicated test account.

Agent may deploy to it: **<no | yes>**.
Credentials come from `<vault or variable name>`.

## Capturing evidence

- Recording: `<to-walkthrough-video | tcut | tool>` — `<fallback if absent>`
- Screenshots: `<tool>`

For a change behind a mode switch or feature flag, confirm the far end
received the call. A healthy container and a green build are not
evidence that an integration is wired up.

## Not verified

- <path or behaviour>: <reason it could not be verified locally>

<!-- Machine-checkable facts for scripts/check-drift.sh. Add one
     drift:file marker per mock scenario or fixture this file relies on. -->
<!-- drift:file <.devcontainer/mock/mappings/tenant.json> -->
