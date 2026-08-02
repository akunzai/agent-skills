# Codex Smoke Comparison

The Codex smoke comparison runs the same isolated `agents-md` fixtures as the
Claude smoke evaluation through the native Codex CLI. Each temporary workspace
registers the evaluated skill at `.agents/skills/agents-md`, Codex's native
project-skill location. It is manually dispatched and diagnostic only: its
result never changes the Claude release decision.

## What it records

`results.json` follows the redacted smoke contract: case identity, observable
fixture evidence, process status, elapsed time, harness version, requested
model and effort, provider, and gateway. Codex CLI JSONL supplies token usage
but does not guarantee a resolved model identifier or dollar cost; those fields
are recorded as `null` with a `not-reported` status instead of inferred values.
The artifact retains neither raw CLI JSONL, stderr, credentials, nor fixture
workspaces.

Malformed JSONL and unsupported reasoning-effort configuration fail safely with
an actionable normalized category. A failing Codex comparison is visible to a
reviewer but is not release-gating.

## Running it

Use the **Codex smoke comparison** workflow from the Actions tab. It uses the
protected `skills-evals` environment and the `OPENROUTER_API_KEY` secret. The
adapter configures Codex's OpenRouter Responses API provider for each run. The
default requested model is `openai/gpt-5.6-luna` at `medium` reasoning effort.

For local experimentation, set `OPENROUTER_API_KEY` only for the invocation and run:

```bash
mise run eval-codex-smoke
```

Keep API keys out of `.env`, source files, issue comments, command output, and
artifacts.
