# Self-Hosted GitHub Instance Detection

Identify custom domain GitHub Enterprise Server (GHES) or GitHub Enterprise Cloud instances.

## Detection Methods

### 1. HTTP API Probe (Fastest)

Inspect HTTP response headers from the API endpoint:

```bash
curl -sI https://<custom-domain>/api/v3
```

- **Header Signature**: Response contains `X-GitHub-Request-Id` or `X-GitHub-Media-Type`.
- **Root API JSON**: `GET https://<custom-domain>/api/v3` returns JSON containing `"installed_version"` or `"github_enterprise_version"`.

### 2. CLI Verification

Check if GitHub CLI (`gh`) is authenticated with the custom host:

```bash
gh auth status --hostname <custom-domain>
```

### 3. Git Config & Environment Variables

Check git configuration and enterprise environment variables:

```bash
git config --get hub.host
echo "${GH_HOST:-${GITHUB_ENTERPRISE_TOKEN:-Not set}}"
```
