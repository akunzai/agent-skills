# Other Git Platform PR / MR CLI Tools

CLI commands and lifecycle workflows for managing Pull Requests (PR) and Merge Requests (MR) on non-GitHub git hosting platforms.

## 1. GitLab Merge Requests (`glab`)

GitLab MR operations, CLI syntax, and non-interactive gotchas are maintained upstream in the official `glab` skill (Single Source of Truth). Do not duplicate commands or CLI gotchas here.

Install the bundled skill via `glab`:

```bash
# User scope (installs to ~/.agents/skills/glab)
glab skills install --global

# Or project scope (installs to .agents/skills/glab)
glab skills install
```

Consult the installed `glab` skill for:
- MR creation, updates, and template handling (`glab mr create`, `glab mr update`)
- Non-interactive safe note creation and stdin piping (`glab mr note create`)
- Threaded discussions and diff comments
- File and image uploads via multipart form data (`--form`)
- Non-interactive pitfalls (avoiding editor hangs, `--input` HTTP 415 errors)

## 2. Gitea / Forgejo (`tea`)

- **Create PR**:
  ```bash
  tea pr create --title "<type>(<scope>): <summary>" --description "<description>"
  ```
- **Update PR on Amend / Force-push**:
  ```bash
  tea pr edit <pr_number> --title "<updated_title>" --description "<updated_description>"
  ```

## 3. Azure DevOps Repos (`az`)

- **Create PR**:
  ```bash
  az repos pr create --title "<type>(<scope>): <summary>" --description "<description>"
  ```
- **Update PR on Amend / Force-push**:
  ```bash
  az repos pr update --id <pr_id> --title "<updated_title>" --description "<updated_description>"
  ```

## 4. Bitbucket

- **Create / Update PR**: Use the Bitbucket REST API or community `bb` CLI. Link Jira tickets using issue keys in commit messages or descriptions (e.g. `JIRA-123`).
