# cheap-dev-workers

Cheap-model roles keep bounded, context-heavy development work out of the
primary session without delegating judgment or Git mutation:

- `repo-explorer`: read-only repository facts with file/line evidence.
- `evidence-collector`: runs a caller-written scenario against a running web
  UI, TUI, or CLI and returns screenshots, recordings, or terminal captures
  with an observed-versus-expected verdict per step. It reports; the primary
  judges correctness and attaches the evidence.
- `log-summarizer`: read-only summaries of caller-approved safe artifacts too
  large for the primary to hold.

Tests, builds, and lint run in the primary, which needs their full output to
act on a failure. The former `check-runner` role is retired for that reason.

Claude, Codex, and Copilot leave model and reasoning effort unset. Callers ask
runtimes that support per-dispatch selection for the cheapest available model
capable of the bounded task and the lowest sufficient effort, starting routine
work at `low`; otherwise the worker inherits the runtime's parent or configured
defaults. Environment, organization, and runtime policies can override that
request, and the plugin does not bypass them.

Cursor CLI loads plugin `agents/*.md` from the Claude Code install. It ignores
`tools:` but enforces `permissionMode: readonly` on the two read-only roles,
so caller skills delegate those there and keep `evidence-collector` work in
primary. See `../../docs/agents/harnesses.md`.

When these named profiles are unavailable, current caller skills may try one
generic subagent with a compact copy of the role's task and permission boundary.
They use the same fallback for explicit pre-execution runtime errors such as
capacity, rate-limit, rejected-model, or launch errors, and skip the generic path
when the runtime cannot enforce that boundary. Once a worker begins its
workload, it is never retried or upgraded; an ambiguous execution status stops
instead of risking duplicate work. Actual model and effort are reported only
from runtime metadata, otherwise as inherited or unknown. Every role is a leaf:
a worker that needs another role hands the need back to the primary.

## Install

From the repository root, run the shared lifecycle manager:

```bash
bash scripts/setup.sh --plugin cheap-dev-workers
```

The interactive setup detects Claude Code, Codex CLI, and GitHub Copilot CLI,
then shows whether the plugin is already installed. Copilot reads the shared
`.claude-plugin` manifests and never touches Codex personal agents. Selecting
Codex also installs the personal agent definitions under
`~/.codex/agents/`. Re-running setup for an already-installed Codex plugin
still syncs these definitions and cleans up unmodified retired agents without
reinstalling the plugin.

Start a new session after installation.

To check or update existing installs after a release, run the upgrade script:

```bash
bash scripts/upgrade.sh --plugin cheap-dev-workers
```

`claude plugin update` only moves when `plugin.json` `version` changed. Codex
personal agents are copies; the root upgrade safely syncs them into
`~/.codex/agents/`. Unmodified copies of known released versions are upgraded;
locally edited or unknown files block the sync before any agent is replaced.
To replace a conflicting file, move it to a backup directory outside
`~/.codex/agents/` and retry the root upgrade script. Setup, upgrade, and
uninstall also remove retired `check-runner.toml` and `commit-writer.toml` files
only when their bytes match a known released version. Edited or unknown retired
files are kept with a warning. A sync conflict stops installation before cleanup.

## Sensitive logs

Low-risk build, lint, and test logs may be delegated after caller review.
Potentially sensitive UTF-8 text up to 10 MiB requires locally installed
Censgate Redact and Betterleaks:

```bash
bash plugins/cheap-dev-workers/scripts/sanitize-log.sh raw.log sanitized.log
```

Only the sanitized artifact may reach `log-summarizer`. Any preprocessing or
residual finding fails closed. A clean result covers installed rules; it is not
proof that no secret remains. Binary, unknown-encoding, oversized, or unsafe
inputs stay in primary or must be split at semantic boundaries.

The script ignores `BETTERLEAKS_CONFIG` and scans an isolated temporary file so
caller-local allowlists cannot weaken the residual gate. Pin reviewed Redact
and Betterleaks versions in the host toolchain; this plugin does not install
optional security binaries.

## Uninstall

Interactively select a runtime; already-uninstalled entries are skipped:

```bash
bash scripts/uninstall.sh --plugin cheap-dev-workers
```
