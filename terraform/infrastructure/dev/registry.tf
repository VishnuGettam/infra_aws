terraform {
  required_version = ">=1.16.5"

  required_providers {
    aws = {
      version = ">6.69"
      source  = "hashicorp/aws"
    }
  }

  # Remote state in the bucket created by terraform/bootstrap.
  # Each environment uses its own key prefix (dev/, uat/, ...) in the same bucket.
  # The bucket is not set here: backends cannot read data sources or variables,
  # so it is passed at init time with -backend-config="bucket=...".
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "ap-south-2"
    encrypt      = true
    use_lockfile = true
  }
}