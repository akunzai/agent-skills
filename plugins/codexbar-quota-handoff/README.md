# codexbar-quota-handoff

Reminds the agent to wrap up when [CodexBar](https://github.com/steipete/CodexBar)
reports that agent's own quota is nearly exhausted — installed as a plugin on
every plugin runtime.

- Tells the agent to surface the quota window and wrap up.
- If the session has unfinished work a later session cannot reconstruct, the
  agent asks before writing a handoff document, then replies with the file
  path.
- With `to-memory` at `~/.agents/skills/to-memory`, the reminder names that
  short-term directory; otherwise the file goes in the current working
  directory, never a temp dir.
- Each agent consumes only its own provider flag.
- Every supported runtime registers `Stop` and `PostToolUse` hooks that
  race safely, so each crossing is reported once.
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
plugin into a selected Claude Code, Codex, or Copilot runtime.
Already-installed plugins are detected and skipped. Pass `--local` to install
from this checkout when testing unpublished changes. Non-interactive callers
select a runtime with `--runtime` and may pass `--yes`.

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

Copilot has no built-in wrap-up command. This plugin's Stop and PostToolUse
hooks inject the procedure; an exit 2 surfaces stderr to the user and the
session continues.

</details>

<details>
<summary>Cursor CLI</summary>

Install into Claude Code: Cursor CLI runs the Claude-nested `PostToolUse`
hook from the Claude Code install. `Stop` is unreliable on the Cursor CLI, so
the reminder path relies on `PostToolUse`. On Cursor, exit 2 does not inject
stderr into the model; the hook instead prints `{"additional_context":"..."}`
on stdout and exits 0.

Setup configures the CodexBar `cursor` provider whenever `cursor-agent` is on
PATH, whichever runtime you select (never a bare `agent` binary, which
collides with Grok's `agent`).

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
helpers, CodexBar rules, and leftover Grok global hook files from older
installs.

To drop leftover Grok files without uninstalling this plugin from other
runtimes:

```bash
bash plugins/codexbar-quota-handoff/scripts/remove-grok.sh
```

That removes the owned `~/.grok/hooks/` files and the CodexBar `grok` rule.
It prints `grok plugin marketplace remove akunzai-agent-skills`; pass `--yes`
to run that command when `grok` is on PATH. Reload Grok hooks or start a new
session afterwards.

## How it works

CodexBar runs the installed `codexbar-quota-flag.sh` on `quota_low`, passing a
provider and an absolute state directory. The agent hook runs
`quota-reminder.sh`, detects its host from native environment variables,
atomically claims the matching flag, emits the wrap-up procedure, and
clears the claim. The reminder no longer suggests `/handoff` or `$handoff`.

Claude Code, Codex, and Copilot load the bundled `hooks/hooks.json` from their
installed plugin; Cursor CLI runs Claude Code's installed copy.

Run the focused checks with:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
```
