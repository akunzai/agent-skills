# Grok Smoke Comparison

The Grok smoke comparison validates the native Grok Build harness against the
shared `agents-md` fixtures. It is manually dispatched and diagnostic only: its
result never changes the Claude release decision.

## What it checks

1. A pinned Grok Build release (`@xai-official/grok@0.2.118`) runs with automatic
   updates disabled.
2. `grok inspect --json` in an isolated workspace discovers project
   `AGENTS.md` instructions and a project-scoped `agents-md` skill under
   `.agents/skills/agents-md`.
3. Headless OpenRouter execution completes one positive (`expected-trigger`) and
   one negative (`expected-non-trigger`) fixture with redacted, normalized
   `results.json` evidence.

Each temporary workspace isolates `HOME` and `GROK_HOME`, disables Claude/Cursor
compatibility skill scans, and registers only the evaluated project skill. The
artifact retains neither raw CLI JSON, stderr, credentials, nor fixture
workspaces.

## Providers

| Provider | Model default | Credential | Use |
|----------|---------------|------------|-----|
| `openrouter` | `x-ai/grok-4.5` | `OPENROUTER_API_KEY` | Routine comparison lane |
| `direct-xai` | `grok-4.5` | `XAI_API_KEY` | One-time calibration only |

Routine workflow runs use OpenRouter only and never inject direct xAI
credentials. Keep API keys out of `.env`, source files, issue comments, command
output, and artifacts.

## Running it

Use the **Grok smoke comparison** workflow from the Actions tab. It uses the
protected `skills-evals` environment and the shared `OPENROUTER_API_KEY` secret.

For local experimentation:

```bash
export OPENROUTER_API_KEY=...   # shell only
mise run eval-grok-smoke
```

## Direct xAI calibration

Run the same two fixtures once through the direct xAI API to see whether the
OpenRouter gateway changes observable skill behavior:

```bash
export XAI_API_KEY=...          # shell only; do not commit
evals/run-grok-smoke.sh \
  --provider direct-xai \
  --model grok-4.5 \
  --artifact-dir "${TMPDIR:-/tmp}/agent-skills-evals/grok-direct-calibration"
```

Record in the issue or PR:

- both providers' case outcomes and workspace-clean flags
- whether either lane failed only on auth, model availability, or sandboxing
- whether OpenRouter remains sufficient for routine comparison

Unless calibration proves OpenRouter cannot preserve required behavior, keep the
routine lane on the protected OpenRouter credential and do not retain direct xAI
credentials in GitHub Actions.

## Review policy

A failing Grok comparison is visible to a reviewer but is not release-gating.
Investigate the normalized case result and discovery block before changing the
skill or fixture.
