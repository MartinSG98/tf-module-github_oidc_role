# For each entry in plan_policies / apply_policies we create a customer-managed policy and attach it
# to the corresponding role. Splitting policies across multiple managed-policy attachments side-steps
# the 6,144-char per-policy limit and lets each logical area (state, IAM, networking, S3, ...) be
# reasoned about and audited independently.

# Plan policies
resource "aws_iam_policy" "plan" {
  for_each = var.plan_policies

  name        = "${var.project_name}_gha_plan_${each.key}-pol-${module.helpers.name_suffix}"
  description = "Plan-time permissions (${each.key}) for ${var.project_name} GitHub Actions"
  policy      = each.value

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "plan_custom" {
  for_each = var.plan_policies

  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.plan[each.key].arn
}

resource "aws_iam_role_policy_attachment" "plan_managed" {
  for_each = toset(var.plan_managed_policy_arns)

  role       = aws_iam_role.plan.name
  policy_arn = each.value
}

# Apply policies
resource "aws_iam_policy" "apply" {
  for_each = var.apply_policies

  name        = "${var.project_name}_gha_apply_${each.key}-pol-${module.helpers.name_suffix}"
  description = "Apply-time permissions (${each.key}) for ${var.project_name} GitHub Actions"
  policy      = each.value

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "apply_custom" {
  for_each = var.apply_policies

  role       = aws_iam_role.apply.name
  policy_arn = aws_iam_policy.apply[each.key].arn
}

resource "aws_iam_role_policy_attachment" "apply_managed" {
  for_each = toset(var.apply_managed_policy_arns)

  role       = aws_iam_role.apply.name
  policy_arn = each.value
}
