output "s3_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.processing.name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.sha256.arn
}
