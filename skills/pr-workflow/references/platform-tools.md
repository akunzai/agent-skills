# Other Git Platform PR / MR CLI Tools

CLI commands and lifecycle workflows for managing Pull Requests (PR) and Merge Requests (MR) on non-GitHub git hosting platforms.

## 1. GitLab Merge Requests (`glab`)

- **Create MR**:
  ```bash
  glab mr create --title "<type>(<scope>): <summary>" --description "<description>"
  ```
- **Update MR on Amend / Force-push**:
  ```bash
  glab mr update <mr_number> --title "<updated_title>" --description "<updated_description>"
  ```
- **Update a multiline issue or MR description from stdin**:
  ```bash
  printf '%s\n' "$updated_description" | glab issue update <issue_number> --description-file -
  printf '%s\n' "$updated_description" | glab mr update <mr_number> --description-file -
  ```
  Prefer the native `--description-file -` path over sending JSON through
  `glab api --input -`. The latter sends a raw request body, and self-hosted
  GitLab may reject it with HTTP 415 unless the request sets the expected JSON
  content type.
- **Attach a screenshot or file to an MR / issue description**:
  ```bash
  glab api "projects/:id/uploads" --form "file=@<path>"
  ```
  `glab` has no dedicated upload command, but `--form` sends
  `multipart/form-data`, which is what the uploads endpoint needs. `:id` is
  replaced with the current repository. Paste the `markdown` field of the JSON
  response into the description verbatim - the `url` it wraps is
  project-relative, so it only resolves inside that project.

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
