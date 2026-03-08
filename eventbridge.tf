resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${var.project_name}-object-created"
  description = "Fires when an object is created in the uploads bucket."

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

resource "aws_cloudwatch_event_target" "ecs" {
  rule     = aws_cloudwatch_event_rule.s3_object_created.name
  arn      = aws_ecs_cluster.main.arn
  role_arn = aws_iam_role.eventbridge.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.sha256.arn
    task_count          = 1
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = data.aws_subnets.default.ids
      assign_public_ip = true
      # No security group specified — uses the default SG for the VPC,
      # which permits all outbound traffic (required for ECR image pull).
      #
      # Production: explicit security group with least-privilege egress rules,
      # or use VPC endpoints so tasks don't need internet access at all.
    }
  }

  # The input_transformer extracts fields from the S3 event JSON and injects
  # them into the ECS RunTask call as container environment variable overrides.
  #
  # input_paths uses JSONPath to pull values out of the event.
  # input_template maps them to container env vars via containerOverrides.
  #
  # Note: input_template must be a raw string — NOT jsonencode(). The <bucket>
  # and <key> tokens are EventBridge's substitution syntax, not valid JSON, so
  # jsonencode() would produce an invalid template.
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }

    input_template = "{\"containerOverrides\":[{\"name\":\"sha256\",\"environment\":[{\"name\":\"S3_BUCKET\",\"value\":\"<bucket>\"},{\"name\":\"S3_KEY\",\"value\":\"<key>\"}]}]}"
  }
}
