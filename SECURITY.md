# Security Policy

## Scope

This project includes shell scripts that execute on users' machines via session
hooks, test scripts, and skill helper scripts. Security issues in any executable
code are in scope.

## Threat model

Skills here are instructions an agent follows with the installer's own
permissions, plus helper scripts it runs. Plugins add hooks that the agent
runtime executes on its own, without the agent choosing to. Nothing in this
repository sandboxes either; the agent runtime's permission prompts and the
installer's review are the controls.

### Capabilities

Every `SKILL.md` declares what it can make the agent do, in frontmatter that
travels with the skill to every runtime and installer:

```yaml
metadata:
  capabilities: shell, network, forge-writes
```

The value is a comma-separated list drawn from the vocabulary below, or `none`
alone. `tests/skill-capabilities.sh` reads this table, so it is the single
source of truth: a new term is added here first. A term is declared when the
skill's `SKILL.md`, references, or scripts direct that action, even behind a
confirmation.

<!-- capabilities:start -->
| Term | The skill can make the agent… |
| --- | --- |
| `none` | do none of the below; allowed only alone |
| `shell` | run shell commands, including the skill's own scripts |
| `network` | reach the network: HTTP fetches, forge APIs, package registries, cloud services |
| `installs-tools` | install software: CLIs, packages, browsers, or other skills, wherever their installer puts them |
| `writes-outside-repo` | write files under `$HOME` or global/system configuration, other than an installer's own files |
| `edits-agent-instructions` | write `AGENTS.md`, `CLAUDE.md`, or agent memory files that later sessions load as instructions |
| `git-history` | rewrite or push git history: rebase, reset, force-with-lease, push, merge |
| `forge-writes` | create or edit issues, pull or merge requests, links, or labels through `gh`/`glab` |
| `reads-transcripts` | read recorded agent session history |
| `browser` | drive a browser, possibly with signed-in state |
| `runs-repo-commands` | execute commands taken from the target repository's content (build/test scripts, task files, docs) |
<!-- capabilities:end -->

`allowed-tools` is deliberately not used: Claude Code treats it as
pre-approval, so it widens what runs without a prompt rather than narrowing it.

### Trust boundaries

- **Target repository content is untrusted input.** Skills tagged
  `runs-repo-commands` run what the repository says to run. In particular,
  `skills/setup-agent-ready-repo/scripts/check-drift.sh --run-entrypoint`
  executes every `drift:entrypoint-cmd` command it reads from the target repo's
  `docs/agents/verification.md` through `sh -c`. Run it only on a repository
  whose documents you would run by hand.
- **Recorded transcripts are untrusted data.** `agentsview-extract` and
  `agentsview-resume` read session history that can contain instructions,
  secrets, and third-party text. Each carries `references/security.md`, which
  keeps transcripts inert and requires review before anything is persisted.
- **Installers fetch from the network.** Skills tagged `installs-tools` ask for
  confirmation before installing. Not every install is pinned: Playwright,
  ffmpeg and `microsoft/webwright` install whatever version their registry
  serves, so their integrity is the vendor's.
- **Agent instructions persist.** Skills tagged `edits-agent-instructions`
  write files that every later session loads. Each shows the exact addition and
  waits for confirmation first.

### Plugin hooks

- **`codexbar-quota-handoff`** registers `Stop` and `PostToolUse` hooks that run
  `scripts/quota-reminder.sh` after every tool call and turn. When CodexBar has
  flagged the agent's quota, the hook injects wrap-up instructions into the
  model's context. Setup writes a helper under `$XDG_DATA_HOME` and flags under
  `$XDG_STATE_HOME`.
- **`spoken-tts`** registers `Stop`, `UserPromptSubmit`, and `PreInvocation`
  hooks. While a conversation has `/spoken on`, the prompt hooks inject speech
  rules into the model's context and the `Stop` hook reads the session
  transcript for the last `<spoken>` line. With the `edge-tts` provider, that
  text (and any passage the user asks to hear) is sent to Microsoft's cloud
  text-to-speech service. `/spoken setup` may install `edge-tts` at runtime
  through `mise`, `uv`, or `pipx`, and stores its config under
  `$XDG_CONFIG_HOME`.

### OWASP Agentic Skills Top 10

Mapped against the
[OWASP Agentic Skills Top 10](https://owasp.github.io/www-project-agentic-skills-top-10/):

| Item | Here |
| --- | --- |
| AST03 Over-Privileged Skills | Addressed: every skill declares `capabilities`; no skill pre-approves tools with `allowed-tools`. |
| AST04 Insecure Metadata | Addressed: `capabilities` is checked against the vocabulary in CI, so a skill cannot understate or invent a term. |
| AST10 Cross-Platform Reuse | Addressed: the declaration lives in the agentskills.io `metadata` map inside `SKILL.md`, so it survives every runtime and `npx skills add`. |
| AST07 Update Drift | Partly: plugins update only on a `version` bump, enforced by `tests/plugin-version-bump.sh`. Catalog skills track the branch; pin a commit to freeze them. |
| AST05 Untrusted External Instructions | Disclosed, not controlled: `agentsview-extract` follows the `agentsview-finding-history` skill that the AgentsView CLI installs, and `write-e2e-tests` follows `microsoft/webwright`. Both are third-party instructions outside this repository. |
| AST01, AST02, AST06, AST08, AST09 | Left to the installer: vet the source, review each skill's `capabilities` before installing, run agents under your runtime's sandbox and permission prompts, and keep an inventory of what you install. |

## Reporting a Vulnerability

**Please do not open a public issue for security vulnerabilities.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security](https://github.com/akunzai/agent-skills/security) tab.
2. Click **Report a vulnerability**.
3. Provide a description, steps to reproduce, and any relevant context.

You will receive an acknowledgement within **7 days**. We will work with you to
understand the issue and coordinate a fix before any public disclosure.

## Supported Versions

Only the latest version on the `main` branch is actively maintained.
