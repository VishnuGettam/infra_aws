resource "aws_s3_bucket" "oidc_test" {
  bucket = "oidc-test-bucket-001"
  region = "ap-south-2"

}