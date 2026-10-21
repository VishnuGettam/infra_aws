provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "Name"        = "AWS-SAA-003"
      "Environment" = "Sandbox"
    }
  }
}