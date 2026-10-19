# GitHub Actions OIDC identity provider.
# An account can only have one provider per URL. The provider was created
# alongside github_actions_role, so import it. If it does not exist, delete
# this import block and Terraform will create it.
import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
