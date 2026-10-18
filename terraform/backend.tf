terraform {
  backend "s3" {
    region = "ap-south-2"
    bucket = "infra-aws-state"
    key = "tf-aws-state.tfstate"
    use_lockfile = true
  }
}