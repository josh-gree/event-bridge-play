# Captures all S3 events arriving on the default bus so we can inspect the raw
# event JSON. Useful for understanding the event structure before writing the
# filter rule and input_transformer in eventbridge.tf.
#
# Production: you'd remove this or gate it behind a variable — you don't want
# to log every S3 event indefinitely.
resource "aws_cloudwatch_log_group" "eventbridge_raw" {
  name              = "/eventbridge/${var.project_name}/raw"
  retention_in_days = 1
}

resource "aws_cloudwatch_event_rule" "s3_raw_debug" {
  name        = "${var.project_name}-s3-raw-debug"
  description = "Forwards all S3 events to CloudWatch for inspection."

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.uploads.id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "s3_raw_debug_logs" {
  rule = aws_cloudwatch_event_rule.s3_raw_debug.name
  arn  = aws_cloudwatch_log_group.eventbridge_raw.arn
}

# EventBridge needs permission to write to the CloudWatch log group.
# This is a resource-based policy on the log group itself — different from IAM
# roles. Without it, EventBridge's writes are silently rejected.
resource "aws_cloudwatch_log_resource_policy" "eventbridge_raw" {
  policy_name = "${var.project_name}-eventbridge-raw"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.eventbridge_raw.arn}:*"
    }]
  })
}
