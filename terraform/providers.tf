provider "aws" {
  profile = "sandbox"

  default_tags {
    tags = {
      Project = "infra_aws"
      ManagedBy = "terraform"
    }
  }
}