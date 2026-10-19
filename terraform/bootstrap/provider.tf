provider "aws" {

  profile = "gh-user" # temporary user for initial local setup 
  region  = var.aws_region

  default_tags {
    tags = {
      Project   = "infra_aws"
      ManagedBy = "terraform"
    }
  }
}