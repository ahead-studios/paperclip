# Running Paperclip Locally with Docker

## Quick start

```bash
docker compose up
```

Opens the Paperclip UI at http://localhost:3100.

Uses the bundled postgres service and runs in `local_trusted` mode (no auth required).

## Production image (with credentials)

The production Dockerfile uses `entrypoint.sh` to inject credentials from environment variables before starting the server. To test locally against the production image:

```bash
docker build -t paperclip .

docker run \
  -e CLAUDE_CODE_OAUTH_TOKEN="your-setup-token" \
  -e CODEX_CREDENTIALS="$(cat ~/.codex/credentials.json)" \
  -e GITHUB_APP_ID="2990013" \
  -e GITHUB_APP_INSTALLATION_ID="113592369" \
  -e PAPERCLIP_GITHUB_APP_PRIVATE_KEY="$(base64 -w 0 < /path/to/app.private-key.pem)" \
  -e DATABASE_URL="postgres://..." \
  -e BETTER_AUTH_SECRET="$(openssl rand -hex 32)" \
  -e BETTER_AUTH_URL="http://localhost:3100" \
  -p 3100:3100 \
  paperclip
```

## Environment variables

### Required in production

| Variable | Source | Description |
|----------|--------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Secrets Manager | OAuth access token for Claude subscription auth. Obtain by running `claude setup-token` locally. |
| `CODEX_CREDENTIALS` | Secrets Manager | Codex subscription token JSON. Obtain by running `codex auth login` locally. |
| `GITHUB_APP_ID` | Inlined in task definition | GitHub App ID (numeric). Used to authenticate the `gh` CLI via App PEM. Value: `2990013`. |
| `GITHUB_APP_INSTALLATION_ID` | Inlined in task definition | Installation ID for the GitHub App on `ahead-studios` org. Value: `113592369`. |
| `PAPERCLIP_GITHUB_APP_PRIVATE_KEY` | Secrets Manager | Base64-encoded PEM private key for the GitHub App. Encode with `base64 -w 0 < app.private-key.pem`. Also used by `paperclip-commit` for verified commits. |
| `GITHUB_TOKEN` | SSM Parameter Store | **Fallback only.** GitHub PAT with `repo` scope. Used if GitHub App vars are not set. |
| `DATABASE_URL` | SSM Parameter Store | PostgreSQL connection string (Aurora in production). |
| `BETTER_AUTH_SECRET` | Secrets Manager | Random secret used by Better Auth for session signing. Generate with `openssl rand -hex 32`. |
| `BETTER_AUTH_URL` | Task definition | Public base URL of the app (e.g. `https://app.example.com`). Required for OAuth redirects and email links. |

### Optional / tunable

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3100` | HTTP port the server listens on. |
| `HOST` | `0.0.0.0` | Bind address. |
| `SERVE_UI` | `true` | Serve the React UI from the same process. |
| `PAPERCLIP_HOME` | `/paperclip` | Data directory for Paperclip state (config, workspaces). |
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` (prod) / `local_trusted` (dev) | Auth mode. `local_trusted` skips login for local dev. |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `private` | Set to `public` only if behind an authenticated reverse proxy. |
| `PAPERCLIP_INSTANCE_ID` | `default` | Instance identifier (used in config path). |

## Configuring agents post-deploy

Once Paperclip is running, create a company and hire agents via the UI or API.

**Example claude agent config** (via `POST /api/companies/:id/agents`):

```json
{
  "name": "claude",
  "adapterType": "claude_local",
  "adapterConfig": {
    "model": "opus",
    "heartbeat": { "enabled": true, "intervalSec": 300 },
    "disallowedTools": [
      "Bash(git push * main*)",
      "Bash(git push * master*)",
      "Bash(git merge *)",
      "Bash(gh pr merge *)"
    ]
  }
}
```

The `disallowedTools` list prevents agents from merging or force-pushing directly; they create PRs instead.

## Token expiry

`CLAUDE_CODE_OAUTH_TOKEN` and Codex tokens expire periodically. When an agent run fails with `claude_auth_required`, generate a fresh token on a locally authenticated machine and update Secrets Manager:

```bash
# Re-generate the Claude setup token
claude setup-token
# Copy the printed token, then:
aws secretsmanager put-secret-value \
  --secret-id /paperclip/anthropic-setup-token \
  --secret-string "sk-ant-oat-..."
```

Then force a new ECS deployment so the task restarts and picks up the fresh token. The CLI uses it directly as a Bearer token on each agent run — no login step needed.
