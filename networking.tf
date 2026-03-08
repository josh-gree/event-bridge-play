# Uses the default VPC that exists in every AWS account.
#
# Play: default VPC + public subnets. Tasks get a public IP so they can reach
# ECR (image pull) and S3. Simple, zero extra resources.
#
# Production: dedicated VPC with private subnets. Tasks should not have public
# IPs. Outbound access to ECR/S3 goes via a NAT gateway or VPC endpoints
# (endpoints keep traffic inside the AWS network and remove per-GB NAT costs).

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
