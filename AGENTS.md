# AGENTS.md

Guidance for human and AI contributors working in this repository.

## 1. Purpose

Paperclip is a control plane for AI-agent companies.
The current implementation target is V1 and is defined in `doc/SPEC-implementation.md`.

## 2. Read This First

Before making changes, read in this order:

1. `doc/GOAL.md`
2. `doc/PRODUCT.md`
3. `doc/SPEC-implementation.md`
4. `doc/DEVELOPING.md`
5. `doc/DATABASE.md`

`doc/SPEC.md` is long-horizon product context.
`doc/SPEC-implementation.md` is the concrete V1 build contract.

## 3. Repo Map

- `server/`: Express REST API and orchestration services
- `ui/`: React + Vite board UI
- `packages/db/`: Drizzle schema, migrations, DB clients
- `packages/shared/`: shared types, constants, validators, API path constants
- `doc/`: operational and product docs

## 4. Dev Setup (Auto DB)

Use embedded PGlite in dev by leaving `DATABASE_URL` unset.

```sh
pnpm install
pnpm dev
```

This starts:

- API: `http://localhost:3100`
- UI: `http://localhost:3100` (served by API server in dev middleware mode)

Quick checks:

```sh
curl http://localhost:3100/api/health
curl http://localhost:3100/api/companies
```

Reset local dev DB:

```sh
rm -rf data/pglite
pnpm dev
```

## 5. Core Engineering Rules

1. Keep changes company-scoped.
Every domain entity should be scoped to a company and company boundaries must be enforced in routes/services.

2. Keep contracts synchronized.
If you change schema/API behavior, update all impacted layers:
- `packages/db` schema and exports
- `packages/shared` types/constants/validators
- `server` routes/services
- `ui` API clients and pages

3. Preserve control-plane invariants.
- Single-assignee task model
- Atomic issue checkout semantics
- Approval gates for governed actions
- Budget hard-stop auto-pause behavior
- Activity logging for mutating actions

4. Do not replace strategic docs wholesale unless asked.
Prefer additive updates. Keep `doc/SPEC.md` and `doc/SPEC-implementation.md` aligned.

5. Keep plan docs dated and centralized.
New plan documents belong in `doc/plans/` and should use `YYYY-MM-DD-slug.md` filenames.

## 6. Database Change Workflow

When changing data model:

1. Edit `packages/db/src/schema/*.ts`
2. Ensure new tables are exported from `packages/db/src/schema/index.ts`
3. Generate migration:

```sh
pnpm db:generate
```

4. Validate compile:

```sh
pnpm -r typecheck
```

Notes:
- `packages/db/drizzle.config.ts` reads compiled schema from `dist/schema/*.js`
- `pnpm db:generate` compiles `packages/db` first

## 7. Verification Before Hand-off

Run this full check before claiming done:

```sh
pnpm -r typecheck
pnpm test:run
pnpm build
```

If anything cannot be run, explicitly report what was not run and why.

## 8. API and Auth Expectations

- Base path: `/api`
- Board access is treated as full-control operator context
- Agent access uses bearer API keys (`agent_api_keys`), hashed at rest
- Agent keys must not access other companies

When adding endpoints:

- apply company access checks
- enforce actor permissions (board vs agent)
- write activity log entries for mutations
- return consistent HTTP errors (`400/401/403/404/409/422/500`)

## 9. UI Expectations

- Keep routes and nav aligned with available API surface
- Use company selection context for company-scoped pages
- Surface failures clearly; do not silently ignore API errors

## 10. Available Skills for Agents

Skills are reusable instruction files loaded into agents. They live in `skills/<name>/SKILL.md`.

| Skill | Purpose |
|---|---|
| `paperclip` | Heartbeat procedure, task checkout, API coordination |
| `slack` | Post Block Kit notifications to a Slack channel |
| `awscli` | Inspect ECS services, CloudWatch logs, SSM/Secrets Manager |
| `grafana-cloud` | Query Loki logs and Mimir metrics |
| `mise` | Install and manage language runtimes (Node, Elixir, Python, etc.) |
| `para-memory-files` | File-based persistent memory across sessions |
| `release` | Coordinate a full Paperclip release |
| `release-changelog` | Generate user-facing changelogs from git history |
| `create-agent-adapter` | Build new adapter packages for new AI coding tools |
| `paperclip-create-agent` | Hire new agents with governance-aware workflow |

### Slack skill — quick reference

Use the `slack` skill to send structured notifications from agent heartbeats.

**When to use:**
- Issue transitions to `blocked` and requires human action
- Milestone completions on high-priority tickets
- Credentials or infrastructure changes are needed (escalation)

**Required env vars (set in agent adapter config):**
- `SLACK_BOT_TOKEN` — Bot OAuth token (`xoxb-...`) with `chat:write` scope
- `SLACK_CHANNEL_ID` — Target channel ID

**Example call (via Claude Skill tool):**
```
skill: "slack"
args: >
  --title "AHE-81: RESEND_API_KEY missing in production"
  --body "Email notifications will not send until RESEND_API_KEY is added to ECS task definition."
  --status blocked
  --agent "SRE Engineer"
  --issue-url "https://app.paperclip.ai/AHE/issues/AHE-81"
```

Full documentation: `skills/slack/SKILL.md`

## 11. Definition of Done

A change is done when all are true:

1. Behavior matches `doc/SPEC-implementation.md`
2. Typecheck, tests, and build pass
3. Contracts are synced across db/shared/server/ui
4. Docs updated when behavior or commands change
