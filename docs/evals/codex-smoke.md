# Codex Smoke Comparison

The Codex smoke comparison runs the same isolated `agents-md` fixtures as the
Claude smoke evaluation through the native Codex CLI. Each temporary workspace
registers the evaluated skill at `.agents/skills/agents-md`, Codex's native
project-skill location. It is manually dispatched and diagnostic only: its
result never changes the Claude release decision.

## What it records

`results.json` follows the redacted smoke contract: case identity, observable
fixture evidence, process status, elapsed time, harness version, requested
model and effort, provider, gateway, and whether the OpenRouter credential was
present (never its value). Codex CLI JSONL supplies token usage
but does not guarantee a resolved model identifier or dollar cost; those fields
are recorded as `null` with a `not-reported` status instead of inferred values.
The artifact retains neither raw CLI JSONL, stderr, credentials, nor fixture
workspaces.

Malformed JSONL, unsupported reasoning-effort configuration, and harness
failures fail safely with actionable normalized categories. Harness failures
also record whether stderr existed, a classified cause, and a SHA-256
fingerprint; they never retain raw stderr or credentials. A failing Codex
comparison is visible to a reviewer but is not release-gating.

## Running it

Use the **Codex smoke comparison** workflow from the Actions tab. It uses the
protected `skills-evals` environment and the `OPENROUTER_API_KEY` secret. The
adapter configures Codex's OpenRouter Responses API provider for each run. The
default requested model is `openai/gpt-5.6-luna` at `medium` reasoning effort.
On GitHub-hosted Ubuntu, the workflow installs Bubblewrap and loads Ubuntu's
packaged `bwrap-userns-restrict` AppArmor profile before running Codex so the
`workspace-write` sandbox can initialize without broadening permissions.

For local experimentation, set `OPENROUTER_API_KEY` only for the invocation and run:

```bash
mise run eval-codex-smoke
```

Keep API keys out of `.env`, source files, issue comments, command output, and
artifacts.
