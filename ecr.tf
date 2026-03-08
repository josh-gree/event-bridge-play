resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  # Play: allows terraform destroy to delete the repository even if it contains
  # images. Production: remove this — losing container images unexpectedly is
  # painful if you need to roll back a deployment.
  force_delete = true

  # Play: MUTABLE lets us overwrite the `latest` tag on each build without
  # changing the task definition or re-applying Terraform.
  #
  # Production: IMMUTABLE tags. Images tagged with git SHA so you always know
  # exactly what's deployed. Pair with ECR lifecycle policies to expire old
  # images and control storage costs.

  image_scanning_configuration {
    scan_on_push = true
  }
}
