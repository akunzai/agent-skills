# Self-Hosted GitLab Instance Detection

Identify custom domain self-hosted GitLab (CE/EE) instances.

## Detection Methods

### 1. HTTP API & Version Probe (Fastest)

Inspect HTTP response headers and version endpoints:

```bash
curl -sI https://<custom-domain>/api/v4/version
```

- **Header Signature**: Response headers contain `x-gitlab-meta` or `Set-Cookie: _gitlab_session=...`.
- **Version API**: If authenticated or open, returns JSON `{"version": "x.y.z", "revision": "..."}`.
- **Help Page**: `curl -sI https://<custom-domain>/help` returns HTML containing GitLab branding metadata.

### 2. CLI Verification

Check if GitLab CLI (`glab`) is configured for the custom host:

```bash
glab config get host
glab api /version --hostname <custom-domain>
```

### 3. Git Config & Environment Variables

Check git configuration and GitLab environment variables:

```bash
git config --get gitlab.host
echo "${GITLAB_HOST:-${CI_SERVER_HOST:-Not set}}"
```
