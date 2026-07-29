output "plan_role_arn" {
  value       = aws_iam_role.plan.arn
  description = "ARN of the role assumed by GitHub Actions to run `terraform plan`"
}

output "plan_role_name" {
  value       = aws_iam_role.plan.name
  description = "Name of the plan role"
}

output "apply_role_arn" {
  value       = aws_iam_role.apply.arn
  description = "ARN of the role assumed by GitHub Actions to run `terraform apply`"
}

output "apply_role_name" {
  value       = aws_iam_role.apply.name
  description = "Name of the apply role"
}

output "github_oidc_provider_arn" {
  value       = local.github_oidc_arn
  description = "ARN of the GitHub OIDC provider trusted by the roles (created by this module if create_oidc_provider, otherwise looked up)"
}
