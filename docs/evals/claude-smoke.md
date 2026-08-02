# Claude Smoke Evaluation

The Claude smoke evaluation is the first model-backed behavioral check for this repository's skills. It runs only when manually dispatched and is not a pull-request, push, or scheduled gate.

## What it checks

The initial suite evaluates `agents-md` in isolated fixtures:

- an expected skill invocation;
- a similar request where the skill must not be invoked; and
- a request that lacks an explicit target and must safely report a blocker.

Each run emits a redacted `results.json` artifact with the requested and resolved model identifiers, Claude Code version, case outcomes, observable fixture evidence, exit status, elapsed time, and aggregate cost. The runner judges cases from temporary-workspace evidence rather than model self-reporting, and fails a case that modifies anything beyond its permitted evidence file. It does not retain raw Claude output, credentials, authorization headers, or fixture workspaces.

The missing-prerequisite case passes only when the temporary workspace remains unchanged. This verifies safe-stop behavior without asking the agent to create a blocker artifact that the skill does not prescribe.

## Running it

Use the **Claude smoke evaluation** workflow from the Actions tab. It uses the protected `skills-evals` environment and requires its `OPENROUTER_API_KEY` secret. The default model is the fixed OpenRouter identifier `anthropic/claude-sonnet-5`; the result records the requested and resolved model identifiers.

For local experimentation, set the OpenRouter credential in your shell and run:

```bash
mise run eval-claude-smoke
```

The default local artifact path is outside the checkout, under the operating system temporary directory. Keep the API key out of `.env`, source files, issue comments, command output, and artifacts.

## Review policy

When changing `agents-md`, manually run this smoke suite before review and link its workflow run in the pull request. A failure is diagnostic until the full Claude baseline is implemented; investigate the normalized case result before changing the skill or fixture.
