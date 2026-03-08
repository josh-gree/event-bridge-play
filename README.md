# S3 → EventBridge → ECS Fargate

An event-driven pipeline that automatically processes objects uploaded to S3. Built as a learning exercise comparing a simple modern EventBridge approach against a more complex SNS/SQS dual-queue pattern used in production systems.

## Architecture

```
S3 upload
    │
    │ (eventbridge = true)
    ▼
EventBridge default bus
    │
    ├── Debug rule → CloudWatch Logs (/eventbridge/s3-sha256/raw)
    │
    └── Object Created rule
            │
            │ RunTask (injects S3_BUCKET + S3_KEY via container overrides)
            ▼
        ECS Fargate Task
            │
            ├── Writes PROCESSING record to DynamoDB
            ├── Downloads object from S3
            ├── Calculates SHA256 hash
            └── Updates DynamoDB → SUCCESS (with hash) or FAILED (with error)
```

## What it demonstrates

- S3 EventBridge integration (`eventbridge = true`) — the modern alternative to SNS/SQS notification chains
- Passing per-event data (bucket + key) into ECS tasks via EventBridge `input_transformer` container overrides
- Separating static config (DynamoDB table name) from per-event data (S3 location)
- A lightweight processing ledger in DynamoDB: `PROCESSING → SUCCESS | FAILED`
- A reprocess script that re-triggers failed objects via S3 metadata-touch (fires a fresh `Object Created` event without re-uploading content)

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured with sufficient permissions
- Docker (for building the ECS task image)

## Deployment

### 1. Stand up infrastructure

```bash
terraform init
terraform apply
```

### 2. Build and push the Docker image

```bash
aws ecr get-login-password --region eu-west-1 \
  | docker login --username AWS --password-stdin \
    $(terraform output -raw ecr_repository_url | cut -d/ -f1)

docker build --platform linux/amd64 -t s3-sha256 app/
docker tag s3-sha256:latest $(terraform output -raw ecr_repository_url):latest
docker push $(terraform output -raw ecr_repository_url):latest
```

> `--platform linux/amd64` is required when building on Apple Silicon — Fargate runs on x86 by default.

### 3. Test the pipeline

Upload a file and watch the logs:

```bash
echo "hello world" | aws s3 cp - s3://$(terraform output -raw s3_bucket_name)/test.txt
aws logs tail /ecs/s3-sha256 --follow --region eu-west-1
```

Or upload 100 test files at once:

```bash
uv run --with boto3 tools/upload_test_files.py --bucket $(terraform output -raw s3_bucket_name)
```

## Processing ledger (DynamoDB)

Every object processed by the pipeline gets a record in DynamoDB:

| Field | Description |
|---|---|
| `bucket` | S3 bucket name (partition key) |
| `key` | S3 object key (sort key) |
| `status` | `PROCESSING`, `SUCCESS`, or `FAILED` |
| `started_at` | ISO 8601 timestamp when the task started |
| `completed_at` | ISO 8601 timestamp when the task finished |
| `sha256` | Hash of the object (SUCCESS only) |
| `error` | Error message (FAILED only) |

Inspect the table:

```bash
aws dynamodb scan \
  --table-name $(terraform output -raw dynamodb_table_name) \
  --region eu-west-1
```

### PROCESSING records

A record remains as `PROCESSING` if the task crashes before updating it. The reprocess script treats any `PROCESSING` record older than 10 minutes as stale.

## Reprocessing failures

Query DynamoDB for `FAILED` and stale `PROCESSING` records and re-trigger each one:

```bash
uv run --with boto3 tools/reprocess.py --table $(terraform output -raw dynamodb_table_name)
```

Re-triggering works by copying the S3 object over itself with updated metadata — this fires a fresh `Object Created` event through the pipeline without re-uploading the content.

Run it repeatedly until no failures remain. With a 30% simulated failure rate, expect 3-4 passes to clear 100 files.

## Simulated failures

`FAILURE_PROBABILITY` is set to `0.3` (30%) in `ecs.tf` to exercise the reprocess path. Set it to `0.0` to disable:

```hcl
{ name = "FAILURE_PROBABILITY", value = "0.0" }
```

Then `terraform apply` and rebuild/push the image.

## Observability

| What | Where |
|---|---|
| Raw S3 events | CloudWatch Logs: `/eventbridge/s3-sha256/raw` |
| Task stdout/stderr | CloudWatch Logs: `/ecs/s3-sha256` |
| Processing status | DynamoDB: `s3-sha256-processing` |
| Task exit codes | ECS console → Clusters → s3-sha256 → Tasks (stopped) |

Watch raw events arrive in real time:

```bash
aws logs tail /eventbridge/s3-sha256/raw --follow --region eu-west-1
```

Watch task output:

```bash
aws logs tail /ecs/s3-sha256 --follow --region eu-west-1
```

## Infrastructure

| File | Purpose |
|---|---|
| `main.tf` | Provider config, data sources |
| `variables.tf` | Input variables |
| `outputs.tf` | Useful resource identifiers |
| `networking.tf` | Default VPC + subnet data sources |
| `s3.tf` | Uploads bucket + EventBridge notification |
| `cloudwatch.tf` | Debug log group + EventBridge rule |
| `ecr.tf` | ECR repository |
| `ecs.tf` | ECS cluster + task definition |
| `iam.tf` | Three IAM roles (task, execution, EventBridge) |
| `eventbridge.tf` | Object Created rule + ECS target with input_transformer |
| `dynamo.tf` | Processing ledger table |

## Play vs production tradeoffs

| Concern | This setup | Production |
|---|---|---|
| S3 → EventBridge | `eventbridge = true` on bucket | Same — this is the modern approach |
| Event routing | EventBridge rule + ECS target | EventBridge Pipe polling SQS (dual-queue pattern) |
| Failure handling | DynamoDB ledger + reprocess script | SQS visibility timeout → automatic retry |
| At-least-once guarantee | Manual reprocess runs | SQS retries + DLQ |
| Terraform state | Local `terraform.tfstate` | S3 backend + DynamoDB locking |
| Networking | Default VPC, public subnets, public IP | Private subnets + NAT gateway or VPC endpoints |
| Image tags | Mutable `latest` | Immutable, tagged with git SHA |
| ECR repos | 1 | 2 (primary + layer cache) |
| Task CPU/memory | 0.25 vCPU / 512 MB | Sized to workload |
| Secrets | IAM role only | Secrets Manager for external credentials |
| Log retention | 7 days | 14+ days |
| Container Insights | Disabled | Enabled |
