<!-- Template. Replace every <angle placeholder>; delete sections that do not apply. -->
<!-- Write the file in English, whatever language the repo chose for its
     tickets: that answer governs what an agent types into the forge, not the
     documents recording the conventions. -->

# Verification

How an agent exercises a change in this repo before it reaches review.
Human setup narrative lives in `<README.md | CONTRIBUTING.md>`; this file
holds only what an agent needs.

## Starting the environment

```sh
<the one non-interactive command>
```

<!-- Service: the command that brings the stack up. Library, CLI or TUI:
     the project's own gate command. Nothing to start, no ports. -->

<!-- drift:forge <github|gitlab|other|none> -->
<!-- A script entrypoint is recorded as a path, a task-runner one as a
     command. Keep the line that applies and delete the other; repeat
     either marker where the gate is genuinely more than one command. -->
<!-- drift:entrypoint <scripts/dev-up.sh> -->
<!-- drift:entrypoint-cmd <mise run check> -->

It never prompts. A step needing a human aborts non-zero naming the
prerequisite — see Human prerequisites below.

**Proof it ran**: `<health endpoint, port check, or a subcommand that
exits zero>`. For a library or CLI this is the built artifact answering
`--version` or `--check`, not a process that stays up.

<!-- Service only; delete for a library, CLI or TUI: -->
Entry point: `<url>`. Test account: `<account>` / `<where the password comes from>`.

## Checks

Record what the lookup cannot give. A task runner already names and
describes its own tasks, so copy none of them here; say where they live
and which command lists them.

| What | Command |
| --- | --- |
| <the gate> | `<command>` |
| <one stage of it> | `<the command that lists them>` |
| <what no task file holds> | `<command>` |

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

<!-- No listening service (library, CLI, TUI) — delete the rest of this
     section and the deployed-environment section below: -->
Not applicable. `<project>` has no listening service, so several agents
can run the gate in the same clone at once.

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

**This document is where the capture rules live**, and the request
document points here rather than restating them. A capture taken on the
developer's own machine carries their account's data, username, and home
paths as readily as a shared environment does. Assert on the frame, a
marker, or fixture data, and crop or mask what the tool happened to be
showing.

For a change behind a mode switch or feature flag, confirm the far end
received the call. A healthy container and a green build are not
evidence that an integration is wired up.

## Not verified

- <path or behaviour>: <reason it could not be verified locally>

<!-- Machine-checkable facts for scripts/check-drift.sh. Add one
     drift:file marker per mock scenario or fixture this file relies on. -->
<!-- drift:file <.devcontainer/mock/mappings/tenant.json> -->
