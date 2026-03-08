terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Play setup: state is local (terraform.tfstate).
  # Production would use a remote backend, e.g.:
  #
  # backend "s3" {
  #   bucket         = "my-terraform-state"
  #   key            = "event-bridge-play/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region
}

# Used to build globally unique names (e.g. S3 bucket names must be unique across all AWS accounts).
data "aws_caller_identity" "current" {}

# Lets us reference the region as a value rather than duplicating the variable.
data "aws_region" "current" {}
