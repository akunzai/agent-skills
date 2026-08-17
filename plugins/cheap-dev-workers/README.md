# cheap-dev-workers

Four cheap-model roles keep bounded, context-heavy development work out of the
primary session without delegating judgment or Git mutation:

- `repo-explorer`: read-only repository facts with file/line evidence.
- `check-runner`: caller-selected checks with auditable result evidence.
- `log-summarizer`: read-only summaries of caller-approved safe artifacts.
- `commit-writer`: commit or PR text for boundaries already decided in primary.

Claude uses Haiku; Codex uses `gpt-5.6-luna`. Missing or failed dispatch falls
back to primary. Claude plugin subagents return relay requests because they
cannot nest. Runtimes that support nesting limit it to explorer → check-runner
or check-runner → log summarizer; correctness never depends on it.

## Install

For Claude Code, install `cheap-dev-workers@akunzai-agent-skills`; `agents/`
is auto-discovered. For Codex, install the personal agent definitions:

```bash
bash plugins/cheap-dev-workers/scripts/setup.sh
```

Start a new session after installation.

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

```bash
bash plugins/cheap-dev-workers/scripts/uninstall.sh
```
