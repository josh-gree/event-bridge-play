resource "aws_cloudwatch_log_group" "ecs_task" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = var.project_name

  # Play: no container insights. Production would enable these for CPU/memory
  # metrics and task-level CloudWatch dashboards.
}

resource "aws_ecs_task_definition" "sha256" {
  family                   = "${var.project_name}-sha256"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  # Minimum Fargate allocation. Fine for small files — production would size
  # based on expected object sizes.
  cpu    = 256
  memory = 512

  # task_role      — assumed by the running container (to call S3, etc.)
  # execution_role — assumed by the ECS control plane (ECR image pull + logs)
  # Both roles are created in iam.tf.
  task_role_arn      = aws_iam_role.ecs_task.arn
  execution_role_arn = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "sha256"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      # S3_BUCKET and S3_KEY are injected at launch time by EventBridge via
      # container overrides. Static config that doesn't change per-event goes
      # here as normal environment variables.
      environment = [
        { name = "DYNAMODB_TABLE", value = aws_dynamodb_table.processing.name },
        { name = "FAILURE_PROBABILITY", value = "0.3" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
