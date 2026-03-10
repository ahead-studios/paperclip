---
name: slack
description: >
  Post structured Slack notifications from any agent. Use when you need to
  escalate a blocker, announce a milestone, or send an update to a Slack
  channel. Requires SLACK_BOT_TOKEN and SLACK_CHANNEL_ID to be set in the
  agent's adapter config.
---

# Slack Skill

Post rich Block Kit messages to Slack from within Paperclip agent heartbeats.

## Authentication

Credentials are injected as environment variables. Never hard-code them.

| Variable | Purpose |
|---|---|
| `SLACK_BOT_TOKEN` | Slack bot OAuth token (`xoxb-...`) with `chat:write` scope |
| `SLACK_CHANNEL_ID` | Target Slack channel ID (e.g. `C0123ABCDEF`) |

If either variable is missing, the skill must fail fast with a clear error message and non-zero exit code. Do not attempt to post without credentials.

To configure for an agent, add these as env vars in the agent's adapter config in Paperclip.

---

## Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `--title` | CLI arg | Yes | Short subject line (e.g. issue title or milestone) |
| `--body` | CLI arg | Yes | Markdown body text (blocker description, update detail) |
| `--issue-url` | CLI arg | No | Full Paperclip issue URL for deep-linking |
| `--status` | CLI arg | No | Issue status (e.g. `blocked`, `in_review`, `done`) |
| `--agent` | CLI arg | No | Agent name for attribution |
| `--channel` | CLI arg | No | Override `SLACK_CHANNEL_ID` for this call only |

---

## Posting a message

Use `curl` to call the Slack Web API `chat.postMessage` endpoint with a Block Kit payload.

### Basic script pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Validate required env vars ---
if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
  echo "ERROR: SLACK_BOT_TOKEN is not set. Add it to the agent adapter config." >&2
  exit 1
fi
if [[ -z "${SLACK_CHANNEL_ID:-}" ]]; then
  echo "ERROR: SLACK_CHANNEL_ID is not set. Add it to the agent adapter config." >&2
  exit 1
fi

# --- Parse args ---
TITLE=""
BODY=""
ISSUE_URL=""
STATUS=""
AGENT_NAME=""
CHANNEL="${SLACK_CHANNEL_ID}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)     TITLE="$2";      shift 2 ;;
    --body)      BODY="$2";       shift 2 ;;
    --issue-url) ISSUE_URL="$2";  shift 2 ;;
    --status)    STATUS="$2";     shift 2 ;;
    --agent)     AGENT_NAME="$2"; shift 2 ;;
    --channel)   CHANNEL="$2";    shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TITLE" || -z "$BODY" ]]; then
  echo "ERROR: --title and --body are required." >&2
  exit 1
fi

# --- Build status emoji ---
STATUS_EMOJI=""
case "${STATUS:-}" in
  blocked)   STATUS_EMOJI="🚨 " ;;
  in_review) STATUS_EMOJI="👀 " ;;
  done)      STATUS_EMOJI="✅ " ;;
  *)         STATUS_EMOJI="" ;;
esac

# --- Build context line ---
CONTEXT_PARTS=()
[[ -n "${AGENT_NAME:-}" ]] && CONTEXT_PARTS+=("Agent: ${AGENT_NAME}")
[[ -n "${STATUS:-}" ]]     && CONTEXT_PARTS+=("Status: ${STATUS}")
CONTEXT_LINE=$(IFS=" | "; echo "${CONTEXT_PARTS[*]}")

# --- Build Block Kit payload ---
# Use jq --arg for all user-supplied fields to prevent JSON injection
# (direct shell interpolation into JSON breaks on quotes, backslashes, newlines)
HEADER_TEXT="${STATUS_EMOJI}${TITLE}"
BLOCKS=$(jq -n \
  --arg header "$HEADER_TEXT" \
  --arg body "$BODY" \
  '[
    {"type": "header", "text": {"type": "plain_text", "text": $header, "emoji": true}},
    {"type": "section", "text": {"type": "mrkdwn", "text": $body}}
  ]')

if [[ -n "${CONTEXT_LINE:-}" ]]; then
  BLOCKS=$(echo "$BLOCKS" | jq --arg ctx "$CONTEXT_LINE" \
    '. += [{"type": "context", "elements": [{"type": "mrkdwn", "text": $ctx}]}]')
fi

if [[ -n "${ISSUE_URL:-}" ]]; then
  BLOCKS=$(echo "$BLOCKS" | jq --arg url "$ISSUE_URL" \
    '. += [{"type": "actions", "elements": [{"type": "button", "text": {"type": "plain_text", "text": "View Issue", "emoji": true}, "url": $url, "style": "primary"}]}]')
fi

PAYLOAD=$(jq -n \
  --arg channel "$CHANNEL" \
  --argjson blocks "$BLOCKS" \
  '{channel: $channel, blocks: $blocks}')

# --- Post to Slack ---
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "https://slack.com/api/chat.postMessage")

OK=$(echo "$RESPONSE" | jq -r '.ok')
if [[ "$OK" != "true" ]]; then
  ERROR=$(echo "$RESPONSE" | jq -r '.error // "unknown error"')
  echo "ERROR: Slack API returned error: ${ERROR}" >&2
  echo "Full response: $RESPONSE" >&2
  exit 1
fi

echo "Message posted successfully to channel ${CHANNEL}"
```

### Minimal one-liner (blocker alert)

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg channel "$SLACK_CHANNEL_ID" --arg text "🚨 Blocked: ${TITLE} — ${BODY}" '{channel: $channel, text: $text}')" \
  "https://slack.com/api/chat.postMessage" | jq '{ok, error}'
```

Use the minimal one-liner for quick pings. Use the full Block Kit script for structured notifications that need attribution and deep-links.

---

## When to call this skill

**Always notify Slack for:**
- Blockers that cannot be resolved within the current heartbeat (status → `blocked`)
- Milestone completions on high-priority tickets
- Issues that require human action (credentials missing, infra change needed, approval required)

**Do not spam:** Skip Slack for routine `done` updates unless the issue was high-priority or blocked.

---

## Rendered output example

```
┌─────────────────────────────────────────────────────┐
│ 🚨 AHE-81: RESEND_API_KEY missing in production     │
│                                                      │
│ Email notifications will not send until              │
│ RESEND_API_KEY is added to the ECS task definition.  │
│                                                      │
│ Agent: SRE Engineer | Status: blocked                │
│                                               [View Issue] │
└─────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `channel_not_found` | Channel ID is wrong or bot not in channel | Invite the bot: `/invite @YourBotName` in the channel |
| `not_authed` | Token missing or invalid | Check `SLACK_BOT_TOKEN` is set and starts with `xoxb-` |
| `missing_scope` | Bot lacks `chat:write` | Add `chat:write` in the Slack app OAuth settings |
| `invalid_blocks` | Malformed Block Kit JSON | Run `jq . <payload>` to validate before posting |

---

## Bot setup (founder action required)

Before any agent can use this skill, the Slack bot app must exist:

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → From scratch.
2. Under **OAuth & Permissions**, add the `chat:write` scope.
3. Install the app to your workspace.
4. Copy the **Bot User OAuth Token** (`xoxb-...`) — set this as `SLACK_BOT_TOKEN` in agent adapter config.
5. In the target channel, run `/invite @YourBotName`.
6. Copy the channel ID (right-click channel → View channel details → ID at bottom) — set as `SLACK_CHANNEL_ID`.
