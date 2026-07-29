# Inputs into this module

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Used to build name of objects we create (consistent with other tf-modules)
variable "environment" {
  type        = string
  description = "The name of the environment in which this module is being invoked"
  validation {
    condition     = contains(["sand", "dev", "uat", "perf", "stage", "prod", "core", "shared"], var.environment)
    error_message = "Environment must be one of sand, dev, uat, perf, stage, prod, core or shared."
  }
}

variable "project_name" {
  type        = string
  description = "Short project identifier; used as the prefix on all resources created by this module (e.g. \"myapp\")"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{1,31}$", var.project_name))
    error_message = "Project name must start with a lowercase letter and use only lowercase letters, digits or underscores (max 32)."
  }
}

variable "github_org" {
  type        = string
  description = "GitHub user or organisation that owns the repository (e.g. \"MartinSG98\")"
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_org))
    error_message = "github_org must be a valid GitHub organisation name."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub repository name within github_org (e.g. \"myapp-infra\")"
  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be a valid GitHub repository name."
  }
}

variable "plan_subject_claims" {
  type        = list(string)
  description = "GitHub OIDC `sub` claim patterns allowed to assume the plan role. If empty defaults to all branches and pull requests of the repo."
  default     = []
}

variable "apply_subject_claims" {
  type        = list(string)
  description = "GitHub OIDC `sub` claim patterns allowed to assume the apply role. If empty defaults to the `main` branch only."
  default     = []
}

variable "create_oidc_provider" {
  type        = bool
  description = "Whether to create the account-wide GitHub OIDC provider. Set to true on the FIRST project bootstrapping CI in an account. If false, the provider must already exist (looked up via data source)."
  default     = false
}

variable "plan_policies" {
  type        = map(string)
  description = "Map of policy short-name -> JSON IAM policy document; one customer-managed policy is created per entry and attached to the plan role. Each value MUST be a valid IAM policy JSON (use jsonencode). Each entry counts towards the 10-policies-per-role quota and is bounded by the 6,144-char managed-policy limit. Should grant only the read-only Describe/List/Get permissions needed for `terraform plan` against the project."
  default     = {}
}

variable "apply_policies" {
  type        = map(string)
  description = "Map of policy short-name -> JSON IAM policy document; one customer-managed policy is created per entry and attached to the apply role. Should grant the full set of permissions needed for end-to-end `terraform apply` of the project."
  default     = {}
}

variable "plan_managed_policy_arns" {
  type        = list(string)
  description = "Additional AWS- or customer-managed policy ARNs to attach to the plan role (e.g. arn:aws:iam::aws:policy/ReadOnlyAccess for a quick read-only blanket)."
  default     = []
}

variable "apply_managed_policy_arns" {
  type        = list(string)
  description = "Additional AWS- or customer-managed policy ARNs to attach to the apply role."
  default     = []
}

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration (seconds) when assuming either of the roles. Must be between 3600 (1h) and 43200 (12h)."
  default     = 3600
  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to be applied to all resources created by this module"
  default     = {}
}

variable "account_shortname" {
  type        = string
  description = "Optional short name for the current account, used in resource name suffixes. Falls back to the raw account ID when not set."
  default     = null
}
