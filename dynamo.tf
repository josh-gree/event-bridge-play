resource "aws_dynamodb_table" "processing" {
  name         = "${var.project_name}-processing"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "bucket"
  range_key    = "key"

  # PAY_PER_REQUEST (on-demand) — no capacity planning needed for a play setup
  # where traffic is unpredictable and low volume.
  #
  # Production: either stay on-demand or switch to PROVISIONED with auto-scaling
  # if you have predictable, high-volume traffic and want to optimise cost.

  attribute {
    name = "bucket"
    type = "S"
  }

  attribute {
    name = "key"
    type = "S"
  }
}
