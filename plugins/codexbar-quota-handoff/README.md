# codexbar-quota-handoff

Reminds Claude Code, Grok Build, or Codex CLI to hand off when
[CodexBar](https://github.com/steipete/CodexBar) reports that agent's own quota
is nearly exhausted.

- Claude Code and Grok Build suggest `/handoff`; Codex suggests `$handoff`.
- Each agent consumes only its own provider flag.
- Claude Code and Codex register `Stop` and `PostToolUse` hooks that race
  safely, so each crossing is reported once. Grok uses a Stop-only global hook
  (see below).
- The default threshold is 90% used and can be changed during setup.

## Setup

Requirements: `jq`, CodexBar, and a checkout of this repository.

```bash
git clone --depth 1 --single-branch https://github.com/akunzai/agent-skills.git
cd agent-skills
bash plugins/codexbar-quota-handoff/scripts/setup.sh --threshold 0.9
```

Setup copies two private helpers to
`${XDG_DATA_HOME:-$HOME/.local/share}/codexbar-quota-handoff/scripts/`, stores
flags under `${XDG_STATE_HOME:-$HOME/.local/state}/codexbar-quota-handoff/`,
adds CodexBar rules only for detected agents, and when `grok` is on PATH
writes `~/.grok/hooks/codexbar-quota-handoff.json`. It prints Claude Code and
Codex plugin-manager commands for `akunzai/agent-skills` without running them
(Grok needs none). Pass `--local` to print this checkout's path instead when
testing unpublished changes.

<details>
<summary>Claude Code</summary>

Install from GitHub:

```bash
claude plugin marketplace add akunzai/agent-skills
claude plugin install codexbar-quota-handoff@akunzai-agent-skills --scope user
```

Reload an active session with `/reload-plugins`.

</details>

<details>
<summary>Grok Build</summary>

No marketplace install is required for the reminder. `setup.sh` installs a
Stop-only global hook at `~/.grok/hooks/codexbar-quota-handoff.json` that
runs the shared runtime helper. Reload hooks from the Hooks tab (`r`) or
start a new session.

Grok Build 1.0.x discovers plugin hooks but does not register them on the
session dispatcher, so a global hook is the reliable path. The hook is
Stop-only because on Grok a PostToolUse `exit 2` is fail-open and would claim
the flag before Stop can surface the reminder.

</details>

<details>
<summary>Codex CLI</summary>

Install from GitHub:

```bash
codex plugin marketplace add akunzai/agent-skills
codex plugin add codexbar-quota-handoff --marketplace akunzai-agent-skills
```

</details>

Open CodexBar once and authorize each provider before setup. If a provider
cannot be reached, setup warns but leaves its rule installed so authorization
can be fixed without rewriting the config.

## Uninstall

```bash
bash plugins/codexbar-quota-handoff/scripts/uninstall.sh
```

Pass `--keep-state` to preserve quota flags. The script removes owned runtime
helpers, the Grok global hook, and CodexBar rules; it prints Claude Code and
Codex plugin removal commands without executing them.

## How it works

CodexBar runs the installed `codexbar-quota-flag.sh` on `quota_low`, passing a
provider and an absolute state directory. The agent hook runs
`quota-reminder.sh`, detects its host from native environment variables,
atomically claims the matching flag, emits the correct handoff reminder, and
clears the claim.

Claude Code and Codex load the bundled `hooks/hooks.json` from their installed
plugin. Grok loads the global hook file written by `setup.sh`.

Run the focused checks with:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
```
