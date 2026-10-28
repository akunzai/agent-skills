# codexbar-quota-handoff

Reminds the agent to wrap up when [CodexBar](https://github.com/steipete/CodexBar)
reports that agent's own quota is nearly exhausted — installed as a plugin on
every plugin runtime.

- Tells the agent to surface the quota window and wrap up.
- If the session has unfinished work a later session cannot reconstruct, the
  agent asks before writing a handoff document, then replies with the file
  path.
- With `agents-memory` at `~/.agents/skills/agents-memory`, the reminder names that
  short-term directory; otherwise the file goes in the current working
  directory, never a temp dir.
- Each agent consumes only its own provider flag.
- Every supported runtime registers `Stop` and `PostToolUse` hooks that
  race safely, so each crossing is reported once.
- The default threshold is 90% used and can be changed during setup.

The `Stop` and `PostToolUse` hooks run after every turn and tool call and, once
CodexBar flags the quota, inject wrap-up instructions into the model's context;
see [SECURITY.md](../../SECURITY.md#plugin-hooks).

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
<summary>Antigravity CLI</summary>

Install into Antigravity:

```bash
agy plugin install ./plugins/codexbar-quota-handoff
```

Antigravity CLI loads `PreInvocation` from the plugin root `hooks.json`. When
CodexBar flags low quota, the hook injects an ephemeral wrap-up reminder via
`injectSteps` before model execution.

</details>

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

Claude Code, Codex, and Copilot load the bundled `hooks/hooks.json` from their
installed plugin; Antigravity CLI loads `hooks.json` from the plugin root.

Run the focused checks with:

```bash
for test in tests/codexbar-quota-handoff-*.sh; do bash "$test"; done
```
