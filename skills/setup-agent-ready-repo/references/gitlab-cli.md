# GitLab CLI and its skill

Every GitLab document this skill writes tells an agent to run `glab`,
and the `glab` skill teaches it the safe command. Check three pieces and
offer each missing one on its own confirmation. `<host>` is the host in
`git remote get-url origin`, self-hosted included.

| Piece | Present when |
| --- | --- |
| CLI | `command -v glab` succeeds |
| Login for this host | `glab auth status --hostname <host>` exits 0 |
| Project skill | `.agents/skills/glab/SKILL.md` and `.claude/skills/glab/SKILL.md` both resolve at the repo root |

**Done when** each row holds or its offer was declined on the record. A
declined piece goes in the hand-back; the documents are still written.

A user-scope copy (`~/.agents/skills/glab/`) serves this developer only;
the project copy is what reaches a teammate's agent. Mention the user
copy, and still offer the project one.

## CLI

With `mise` on `PATH`, offer `mise use -g glab` (the registry maps it to
`gitlab:gitlab-org/cli`). User scope, because the CLI is a developer
tool rather than a build dependency; pin it in the repo's `mise.toml`
only when the developer asks. Without `mise`, point at the install
section of <https://gitlab.com/gitlab-org/cli>.

## Login

A human-only step: `glab auth login --hostname <host>` prompts for a
token. Ask the developer to run it themselves (in Claude Code,
`! glab auth login --hostname <host>`), then rerun `glab auth status`.
The token stays in their terminal; this pass never asks for it or puts
it on a command line.

Then rerun the ladder. A repo that fell to "neither probe" only because
`glab` was missing or logged out now resolves to GitLab.

## Project skill

Run only the step whose path is missing. Both write under the repo root:
show the paths before running, and list them in the hand-back as ready
to commit.

1. `.agents/skills/glab/`: `glab skills install glab` (experimental).
   Without `--global` it installs at project scope, at the git root;
   `--force` overwrites an existing copy.
2. `.claude/skills/glab`, read by Claude Code and Copilot CLI:
   `mkdir -p .claude/skills && ln -s ../../.agents/skills/glab .claude/skills/glab`.
