# GitHub Actions OIDC provider for AWS.
#
# IMPORTANT: There can be only ONE OIDC provider per URL per account. Set create_oidc_provider = true
# only on the FIRST module instance bootstrapping CI in this account; for every subsequent project,
# leave create_oidc_provider = false (the default) and we'll look up the existing provider instead.
#
# AWS now natively trusts GitHub's OIDC certificate chain so the thumbprint is no longer used for
# verification, but the resource still requires thumbprint_list to be set. We supply the official
# placeholder published by GitHub - any value is accepted by the API:
#   https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.github_oidc_url}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = (!var.create_oidc_provider && var.existing_oidc_provider_arn == null) ? 1 : 0

  url = "https://${local.github_oidc_url}"
}
