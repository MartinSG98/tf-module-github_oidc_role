locals {
  # Used to tag all resources created by the module
  tags = merge(
    var.tags,
    { "InfraModule" = join(":", compact(["tf-module-github_oidc_role", lookup(var.tags, "InfraModule", "")])) }
  )

  github_oidc_url = "token.actions.githubusercontent.com"

  # Resolve the OIDC provider ARN from either the resource we created (if create_oidc_provider) or
  # from the existing account-wide provider via data source. one() returns the single element of a
  # list with 0 or 1 items, or null if empty - perfect for count-based optional resources.
  github_oidc_arn = coalesce(
    one(aws_iam_openid_connect_provider.github[*].arn),
    one(data.aws_iam_openid_connect_provider.github[*].arn),
  )

  # Default GitHub OIDC `sub` claim patterns if the caller doesn't override them.
  # See: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims
  default_plan_subjects = [
    "repo:${var.github_org}/${var.github_repository}:pull_request",
    "repo:${var.github_org}/${var.github_repository}:ref:refs/heads/*",
  ]

  default_apply_subjects = [
    "repo:${var.github_org}/${var.github_repository}:ref:refs/heads/main",
  ]

  plan_subjects  = length(var.plan_subject_claims) > 0 ? var.plan_subject_claims : local.default_plan_subjects
  apply_subjects = length(var.apply_subject_claims) > 0 ? var.apply_subject_claims : local.default_apply_subjects
}
