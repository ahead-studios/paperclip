---
name: grafana-cloud
description: >
  Query logs from Grafana Cloud Loki using logcli, and query or inspect metrics
  from Grafana Cloud Mimir using mimirtool. Use when debugging issues, tailing
  logs, investigating errors, or checking metric values and alert rules.
---

# Grafana Cloud Skill

Query logs (Loki) and metrics (Mimir/Prometheus) from Grafana Cloud.

## Authentication

Credentials are injected as environment variables. Never hard-code them.

| Variable | Purpose |
|---|---|
| `GRAFANA_LOKI_URL` | Loki endpoint, e.g. `https://logs-prod-eu-west-0.grafana.net` |
| `GRAFANA_LOKI_USERNAME` | Loki instance ID (numeric) |
| `GRAFANA_LOKI_API_KEY` | Grafana Cloud API key with Logs Reader role |
| `GRAFANA_MIMIR_URL` | Mimir endpoint, e.g. `https://prometheus-prod-01-eu-west-0.grafana.net` |
| `GRAFANA_MIMIR_USERNAME` | Mimir instance ID (numeric) |
| `GRAFANA_MIMIR_API_KEY` | Grafana Cloud API key with Metrics Reader role |

If a variable is missing, stop and post a comment asking for it to be added as a company secret.

---

## Loki — Querying Logs with `logcli`

### Basic auth pattern

Always pass these flags (or set env vars):

```bash
logcli \
  --addr="$GRAFANA_LOKI_URL" \
  --username="$GRAFANA_LOKI_USERNAME" \
  --password="$GRAFANA_LOKI_API_KEY" \
  <subcommand>
```

To avoid repetition, export a helper alias at the top of any script:

```bash
LOKI_AUTH="--addr=$GRAFANA_LOKI_URL --username=$GRAFANA_LOKI_USERNAME --password=$GRAFANA_LOKI_API_KEY"
```

### Tail live logs

```bash
# Tail logs for a specific ECS service
logcli $LOKI_AUTH tail '{service="my-service",env="production"}'

# Tail with a filter
logcli $LOKI_AUTH tail '{service="my-service"} |= "ERROR"'
```

### Query logs for a time range

```bash
# Last 1 hour of errors
logcli $LOKI_AUTH query \
  '{service="my-service"} |= "ERROR"' \
  --since=1h \
  --limit=100

# Specific time window (RFC3339)
logcli $LOKI_AUTH query \
  '{service="my-service"}' \
  --from="2024-01-15T10:00:00Z" \
  --to="2024-01-15T10:30:00Z"
```

### Common LogQL patterns

```bash
# Filter by log level
'{service="my-service"} | json | level="error"'

# Extract and filter structured JSON logs
'{service="my-service"} | json | request_path="/api/health"'

# Rate of errors over time
'rate({service="my-service"} |= "ERROR" [5m])'

# Count by status code
'sum by (status) (count_over_time({service="my-service"} | json [5m]))'
```

### Discover available labels

```bash
# List all label names
logcli $LOKI_AUTH labels

# List values for a specific label
logcli $LOKI_AUTH labels service
```

### Output formats

```bash
# Default: timestamp + log line
# Add --output=raw for just log lines
# Add --output=jsonl for NDJSON (useful for piping to jq)
logcli $LOKI_AUTH query '{service="my-service"}' --output=jsonl | jq '.line | fromjson'
```

---

## Mimir — Querying Metrics with `mimirtool`

### Environment setup

```bash
export MIMIR_ADDRESS="$GRAFANA_MIMIR_URL"
export MIMIR_TENANT_ID="$GRAFANA_MIMIR_USERNAME"
export MIMIR_API_USER="$GRAFANA_MIMIR_USERNAME"
export MIMIR_API_KEY="$GRAFANA_MIMIR_API_KEY"
```

With these exported, you can omit flags from most `mimirtool` commands.

### Query a metric value (instant)

```bash
# Current value of a metric
mimirtool query 'up{job="my-service"}'

# With explicit auth (no env vars)
mimirtool query \
  --address="$GRAFANA_MIMIR_URL" \
  --id="$GRAFANA_MIMIR_USERNAME" \
  --key="$GRAFANA_MIMIR_API_KEY" \
  'rate(http_requests_total[5m])'
```

### Query over a time range

```bash
# Error rate over last hour, sampled every 5 minutes
mimirtool query-range \
  --start="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --step=5m \
  'rate(http_server_errors_total[5m])'
```

### List and inspect alert rules

```bash
# List all rule groups
mimirtool rules list

# Print rules for a specific namespace
mimirtool rules print --namespace=my-service
```

### Validate alert rules locally

```bash
# Validate a rules file before pushing
mimirtool rules check my-alerts.yaml
```

### Check series cardinality

```bash
# Top 10 highest cardinality metrics
mimirtool analyze prometheus --address="$GRAFANA_MIMIR_URL" \
  --id="$GRAFANA_MIMIR_USERNAME" \
  --key="$GRAFANA_MIMIR_API_KEY"
```

---

## Tips

- **Time ranges:** `logcli` accepts `--since=1h`, `--since=30m`. `mimirtool query-range` needs ISO timestamps — use `date -u` to generate them.
- **Label discovery:** Always run `logcli labels` first if you're unsure what labels are available for your service.
- **Rate limits:** Grafana Cloud has query rate limits. For large investigations, use narrower time ranges and increase specificity of label selectors before broadening.
- **JSON logs:** If the service emits structured JSON logs, use `| json` in LogQL to parse fields and filter on them directly.
