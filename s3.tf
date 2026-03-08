resource "aws_s3_bucket" "uploads" {
  # Account ID suffix ensures the name is globally unique across all AWS accounts.
  bucket = "${var.project_name}-uploads-${data.aws_caller_identity.current.account_id}"

  # Play: allows terraform destroy to delete the bucket even if it contains
  # objects. Production: remove this — you want Terraform to refuse to delete
  # a non-empty bucket, forcing a deliberate manual decision before data is lost.
  force_destroy = true

  # Play: no versioning, encryption, or access logging.
  #
  # Production would add:
  #   aws_s3_bucket_versioning        — recover from accidental deletes/overwrites
  #   aws_s3_bucket_server_side_encryption_configuration — SSE-S3 or SSE-KMS
  #   aws_s3_bucket_logging           — access logs to a separate audit bucket
  #   aws_s3_bucket_lifecycle_configuration — expire old versions, abort incomplete uploads
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  # This single flag is what starts the pipeline. S3 will emit all object events
  # (created, deleted, restored, etc.) to the default EventBridge bus.
  # The EventBridge rule we add later filters down to Object Created only.
  eventbridge = true
}
