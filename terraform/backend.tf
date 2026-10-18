terraform {
  backend "s3" {
    region = "ap-south-2"
    bucket = "infra-aws-state-512093097289-ap-south-2-an"
    key = "tf-aws-state.tfstate"
    use_lockfile = true
    encrypt = true
  }
}