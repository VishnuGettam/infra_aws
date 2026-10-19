variable "aws_region" {
  description = "AWS region where our infrastructure is being build"
  type        = string
}

variable "github_repo" {
  description = "github repo for the aws terraform project"
  type        = string
}

variable "github_org" {
  description = "github organisation details"
  type        = string
}

variable "github_actions_role_name" {
  description = "existing IAM role assumed by GitHub Actions via OIDC"
  type        = string
  default     = "github_actions_role"
}

variable "github_org_id" {
  description = "numeric GitHub owner ID used in the OIDC sub claim"
  type        = string
}

variable "github_repo_id" {
  description = "numeric GitHub repository ID used in the OIDC sub claim"
  type        = string
}
