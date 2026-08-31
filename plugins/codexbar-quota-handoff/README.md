# codexbar-quota-handoff

Reminds Claude Code, Grok Build, Codex CLI, or GitHub Copilot CLI to hand off
when [CodexBar](https://github.com/steipete/CodexBar) reports that agent's own
quota is nearly exhausted.

- Claude Code, Grok Build, and Copilot suggest `/handoff`; Codex suggests
  `$handoff`.
- Each agent consumes only its own provider flag.
- Claude Code, Codex, and Copilot register `Stop` and `PostToolUse` hooks that
  race safely, so each crossing is reported once. Grok uses a Stop-only global
  hook (see below).
- The default threshold is 90% used and can be changed during setup.

## Setup

Requirements: `jq`, CodexBar, and a checkout of this repository.

```bash
git clone --depth 1 --single-branch https://github.com/akunzai/agent-skills.git
cd agent-skills
bash scripts/setup.sh --plugin codexbar-quota-handoff --threshold 0.9
```

Setup copies the flag-writer helper to
`${XDG_DATA_HOME:-$HOME/.local/share}/codexbar-quota-handoff/scripts/`, stores
flags under `${XDG_STATE_HOME:-$HOME/.local/state}/codexbar-quota-handoff/`,
adds CodexBar rules only for detected agents, and interactively installs the
plugin into a selected Claude Code, Codex, or Copilot runtime. Already-installed
plugins are detected and skipped. When `grok` is on PATH it also writes
`~/.grok/hooks/codexbar-quota-reminder.sh` and
`~/.grok/hooks/codexbar-quota-handoff.json` (Grok needs no marketplace
install). Pass `--local` to install from this checkout when testing unpublished
changes. Non-interactive callers select a runtime with `--runtime` and may pass
`--yes`.

Upgrade interactively and refresh the local helper/config integration with:

```bash
bash scripts/upgrade.sh --plugin codexbar-quota-handoff --threshold 0.9
```

<details>
<summary>Claude Code</summary>

Reload an active session with `/reload-plugins`.

</details>

<details>
<summary>Codex CLI</summary>

The root lifecycle manager registers the marketplace and plugin.

</details>

<details>
<summary>GitHub Copilot CLI</summary>

Copilot reads the same `.claude-plugin/marketplace.json` and
`.claude-plugin/plugin.json` this repository already ships, and registers the
bundled `hooks/hooks.json` as-is — there is no Copilot-specific manifest.
Start a new session after installing.

Copilot has no built-in handoff command, but it exposes every loaded skill as
a slash command, so `/handoff` works once this repository's `handoff` skill is
installed (verify with `copilot skill list`).

</details>

<details>
<summary>Grok Build</summary>

No marketplace install is required for the reminder. The root setup installs a
Stop-only global hook at `~/.grok/hooks/codexbar-quota-handoff.json` and copies
the reminder script to `~/.grok/hooks/codexbar-quota-reminder.sh`. Reload hooks
from the Hooks tab (`r`) or start a new session.

Grok Build 1.0.x discovers plugin hooks but does not register them on the
session dispatcher, so a global hook is the reliable path. The hook is
Stop-only because on Grok a PostToolUse `exit 2` is fail-open and would claim
the flag before Stop can surface the reminder.

</details>

Open CodexBar once and authorize each provider before setup. If a provider
cannot be reached, setup warns but leaves its rule installed so authorization
can be fixed without rewriting the config.

## Uninstall

```bash
bash scripts/uninstall.sh --plugin codexbar-quota-handoff
```

Select a runtime interactively; installed status is detected before removal.
Pass `--keep-state` to preserve quota flags. The script removes owned runtime
helpers, CodexBar rules, and the Grok global hook files.

## How it works

CodexBar runs the installed `codexbar-quota-flag.sh` on `quota_low`, passing a
provider and an absolute state directory. The agent hook runs
`quota-reminder.sh`, detects its host from native environment variables,
atomically claims the matching flag, emits the correct handoff reminder, and
clears the claim.

Claude Code, Codex, and Copilot load the bundled `hooks/hooks.json` from their
installed plugin. Grok loads the global hook file and reminder script written by
the root setup entry point.

Run the focused checks with:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
```
