---
name: awscli
description: >
  Use the AWS CLI to inspect and interact with AWS infrastructure. Use when
  you need to check ECS service status, fetch CloudWatch logs, read SSM
  parameters or Secrets Manager values, or inspect ECR images. Auth is
  automatic via the ECS task IAM role — no credentials needed.
---

# AWS CLI Skill

Interact with AWS from within Paperclip agents running on ECS.

## Authentication

When running inside ECS, the AWS CLI automatically authenticates via the **ECS task IAM role**. No credentials need to be set. If you're running locally (not on ECS), ensure `AWS_PROFILE` or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` are set.

The deployment region is typically available via:

```bash
AWS_REGION="${AWS_REGION:-eu-west-1}"
```

Always use `--region "$AWS_REGION"` or set `AWS_DEFAULT_REGION` to avoid region mismatches.

---

## ECS — Inspect Services and Tasks

### List all ECS clusters

```bash
aws ecs list-clusters --region "$AWS_REGION"
```

### List services in a cluster

```bash
aws ecs list-services \
  --cluster my-cluster \
  --region "$AWS_REGION"
```

### Describe a service (deployments, desired/running count, events)

```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --region "$AWS_REGION" \
  | jq '.services[0] | {status, desiredCount, runningCount, pendingCount, deployments}'
```

### List running tasks for a service

```bash
aws ecs list-tasks \
  --cluster my-cluster \
  --service-name my-service \
  --region "$AWS_REGION"
```

### Describe a task (container status, stopped reason, exit code)

```bash
TASK_ARN="arn:aws:ecs:eu-west-1:123456789:task/my-cluster/abc123"

aws ecs describe-tasks \
  --cluster my-cluster \
  --tasks "$TASK_ARN" \
  --region "$AWS_REGION" \
  | jq '.tasks[0] | {lastStatus, stoppedReason, containers: [.containers[] | {name, lastStatus, exitCode, reason}]}'
```

### Check recent service events (useful for deployment issues)

```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --region "$AWS_REGION" \
  | jq '.services[0].events[:10]'
```

---

## CloudWatch Logs — Fetch Application Logs

ECS services typically log to CloudWatch log groups named `/ecs/<service-name>`.

### List log streams for a service

```bash
aws logs describe-log-streams \
  --log-group-name "/ecs/my-service" \
  --order-by LastEventTime \
  --descending \
  --max-items 10 \
  --region "$AWS_REGION" \
  | jq '.logStreams[].logStreamName'
```

### Fetch recent log events from a stream

```bash
aws logs get-log-events \
  --log-group-name "/ecs/my-service" \
  --log-stream-name "ecs/my-service/abc123" \
  --start-from-head \
  --region "$AWS_REGION" \
  | jq '.events[].message'
```

### Filter logs by pattern (across all streams)

```bash
aws logs filter-log-events \
  --log-group-name "/ecs/my-service" \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region "$AWS_REGION" \
  | jq '.events[].message'
```

### Tail logs (CloudWatch Insights)

```bash
# Run a CloudWatch Insights query for the last 30 minutes
aws logs start-query \
  --log-group-name "/ecs/my-service" \
  --start-time $(date -d '30 minutes ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50' \
  --region "$AWS_REGION"

# Then fetch the results (use the queryId from above)
aws logs get-query-results \
  --query-id <queryId> \
  --region "$AWS_REGION"
```

---

## SSM Parameter Store — Read Config

```bash
# Read a single parameter (plaintext)
aws ssm get-parameter \
  --name "/myapp/production/database-url" \
  --region "$AWS_REGION" \
  | jq -r '.Parameter.Value'

# Read a SecureString parameter (decrypted)
aws ssm get-parameter \
  --name "/myapp/production/api-key" \
  --with-decryption \
  --region "$AWS_REGION" \
  | jq -r '.Parameter.Value'

# List all parameters under a path
aws ssm get-parameters-by-path \
  --path "/myapp/production/" \
  --recursive \
  --region "$AWS_REGION" \
  | jq '.Parameters[] | {Name, Type}'
```

---

## Secrets Manager — Read Secrets

```bash
# Fetch a secret value
aws secretsmanager get-secret-value \
  --secret-id "myapp/production/db-credentials" \
  --region "$AWS_REGION" \
  | jq -r '.SecretString | fromjson'
```

---

## ECR — Inspect Container Images

```bash
# List images in a repository (most recent first)
aws ecr describe-images \
  --repository-name my-service \
  --region "$AWS_REGION" \
  | jq '[.imageDetails | sort_by(.imagePushedAt) | reverse | .[:5][] | {tags: .imageTags, pushedAt: .imagePushedAt, sizeBytes: .imageSizeInBytes}]'
```

---

## Tips

- **jq is your friend:** AWS CLI JSON output is verbose. Always pipe to `jq` to extract what you need.
- **Permissions:** If a command returns `AccessDeniedException`, the ECS task role lacks that permission. Note it in a comment and ask for the permission to be granted — don't try to work around it.
- **Dry-run:** For write operations, prefer `--dry-run` where available. For ECS, describe before you modify.
- **Region:** The deployment is in `eu-west-1`. Always pass `--region` explicitly or set `AWS_DEFAULT_REGION=eu-west-1` at the top of scripts.
