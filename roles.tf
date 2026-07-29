# Plan role - assumed by GitHub Actions to run `terraform plan`.
# Trust limited to the configured GitHub repo and the (default: any-branch / pull-request) sub claims.
resource "aws_iam_role" "plan" {
  name                 = "${var.project_name}_gha_plan-role-${module.helpers.name_suffix}"
  description          = "GitHub Actions OIDC role for `terraform plan` of ${var.project_name}"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.github_oidc_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.github_oidc_url}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.github_oidc_url}:sub" = local.plan_subjects
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Apply role - assumed by GitHub Actions to run `terraform apply`.
# Trust is intentionally narrower than `plan` (default: only the main branch).
resource "aws_iam_role" "apply" {
  name                 = "${var.project_name}_gha_apply-role-${module.helpers.name_suffix}"
  description          = "GitHub Actions OIDC role for `terraform apply` of ${var.project_name}"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.github_oidc_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.github_oidc_url}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.github_oidc_url}:sub" = local.apply_subjects
          }
        }
      }
    ]
  })

  tags = local.tags
}
