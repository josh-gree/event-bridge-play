variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources."
  type        = string
  default     = "s3-sha256"
}

variable "image_tag" {
  description = "Docker image tag to deploy to ECS."
  type        = string
  default     = "latest"
}
