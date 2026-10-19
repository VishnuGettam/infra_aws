output "github_actions_role_arn" {
  description = "Role ARN for the AWS_ROLE_ARN GitHub repository variable"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "state_bucket_name" {
  description = "S3 bucket holding the infrastructure Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}
