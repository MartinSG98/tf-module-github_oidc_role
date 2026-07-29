# tf-module-github_oidc_role

Bootstraps the IAM resources needed for a project to be deployed end-to-end from a GitHub Actions
workflow with no long-lived AWS credentials, using GitHub's OIDC identity provider as the trust
anchor.

For each project (e.g. `myapp`) the module creates **two** distinct roles:

* **`<project>_gha_plan-role-<env-region-account>`** - assumed by jobs running `terraform plan`.
  Trust is permissive (any branch + pull requests by default) and the attached permissions are
  read-only (Describe / List / Get on every service the project's TF module touches, plus state-lock
  acquire/release).
* **`<project>_gha_apply-role-<env-region-account>`** - assumed by jobs running `terraform apply`.
  Trust is restricted (only the `main` branch by default) and the attached permissions cover the full
  set required for an end-to-end deployment of the project's TF module.

Both roles trust the account-wide GitHub OIDC provider
(`arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`). The module can
optionally create that provider on the first project bootstrapping CI in an account.

## Resources created

* `aws_iam_openid_connect_provider.github` - account-wide OIDC IdP. Optional, only when
  `create_oidc_provider = true`. Looked up via data source otherwise.
* `aws_iam_role.plan` - the plan role.
* `aws_iam_role.apply` - the apply role.
* One `aws_iam_policy` + `aws_iam_role_policy_attachment` for every entry in `plan_policies` and
  `apply_policies`. Splitting policies across separate attachments side-steps the 6,144-char per
  managed-policy limit.
* `aws_iam_role_policy_attachment` for any AWS-managed policy ARNs supplied via
  `plan_managed_policy_arns` / `apply_managed_policy_arns`.

## Inputs

* `environment`: deployment environment short name (sand, dev, uat, perf, stage, prod, core or shared).
* `project_name`: short identifier used as the prefix of every resource (e.g. `myapp`).
* `github_org`: GitHub organisation that owns the repo (e.g. `MartinSG98`).
* `github_repository`: the repo name (e.g. `myapp-infra`).
* `plan_subject_claims`: list of OIDC `sub` patterns that may assume the plan role. Defaults to all
  branches and pull requests of `github_org/github_repository` if empty.
* `apply_subject_claims`: same, for the apply role. Defaults to `refs/heads/main` only.
* `create_oidc_provider`: bool; create the account-wide GitHub OIDC provider. Set to `true` only on
  the first stack bootstrapping CI in the account; default `false`.
* `plan_policies`: map of `name -> JSON IAM policy doc` - one customer-managed policy per entry.
  Should grant only the read-only permissions needed for `terraform plan`.
* `apply_policies`: same shape; should grant the full set required for `terraform apply`.
* `plan_managed_policy_arns`: list of additional managed policy ARNs to attach to the plan role
  (e.g. `arn:aws:iam::aws:policy/ReadOnlyAccess`).
* `apply_managed_policy_arns`: same, for the apply role.
* `max_session_duration`: max duration of an assumed-role session in seconds (3600-43200).
* `tags`: extra tags merged into the standard `InfraModule` tag.

## Outputs

* `plan_role_arn`, `plan_role_name`
* `apply_role_arn`, `apply_role_name`
* `github_oidc_provider_arn`

## GitHub Actions usage

Configure each job to assume the role via OIDC:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GHA_PLAN_ROLE_ARN }}
          aws-region: eu-west-2
      - run: terraform init && terraform plan
```

The `apply` job is identical except it assumes the apply role and is gated on a protected `main`
branch / environment-approval rule, matching the trust policy on that role.

## Example: full project bootstrap

Wire up plan/apply roles for a project. Each `plan_policies` / `apply_policies` entry is a
self-contained logical chunk so it stays under the 6,144-char managed-policy limit.

```hcl
module "myapp_gha" {
  source = "git::https://github.com/MartinSG98/tf-module-github_oidc_role.git?ref=1.0.0"

  environment       = var.environment
  project_name      = "myapp"
  github_org        = "MartinSG98"
  github_repository = "myapp-infra"

  # Bootstrap the account-wide OIDC provider on the first project; flip back to false afterwards.
  create_oidc_provider = false

  # Quick-and-dirty: every read-only API in the account is allowed for the planner. Combine with the
  # state-lock policy below so `terraform plan` can acquire/release its state lock.
  plan_managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  plan_policies = {
    state = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "TFStateBucketRead"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
          Resource = "arn:aws:s3:::terraformstate-s3-core-ew2-mainaccount"
        },
        {
          Sid      = "TFStateObjectsRead"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "arn:aws:s3:::terraformstate-s3-core-ew2-mainaccount/*"
        },
        {
          Sid    = "TFStateLock"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:DeleteItem",
            "dynamodb:DescribeTable",
          ]
          Resource = "arn:aws:dynamodb:eu-west-2:*:table/terraform-locks*"
        }
      ]
    })
  }

  apply_policies = {
    state = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "TFStateBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
          Resource = "arn:aws:s3:::terraformstate-s3-core-ew2-mainaccount"
        },
        {
          Sid      = "TFStateObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "arn:aws:s3:::terraformstate-s3-core-ew2-mainaccount/*"
        },
        {
          Sid    = "TFStateLock"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:DeleteItem",
            "dynamodb:DescribeTable",
          ]
          Resource = "arn:aws:dynamodb:eu-west-2:*:table/terraform-locks*"
        }
      ]
    })

    networking = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ec2:Describe*",
            "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
            "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
            "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
            "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
            "ec2:CreateTags", "ec2:DeleteTags",
            "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface", "ec2:DetachNetworkInterface",
            "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
          ]
          Resource = "*"
        }
      ]
    })

    iam = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
            "iam:UpdateAssumeRolePolicy",
            "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
            "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
            "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
            "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
            "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
            "iam:CreateServiceLinkedRole",
          ]
          Resource = [
            "arn:aws:iam::*:role/myapp_*", "arn:aws:iam::*:role/myapp-*",
            "arn:aws:iam::*:policy/myapp_*", "arn:aws:iam::*:policy/myapp-*",
            "arn:aws:iam::*:role/aws-service-role/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = "iam:PassRole"
          Resource = ["arn:aws:iam::*:role/myapp_*", "arn:aws:iam::*:role/myapp-*"]
          Condition = {
            StringEquals = {
              "iam:PassedToService" = [
                "lambda.amazonaws.com", "apigateway.amazonaws.com",
                "bedrock.amazonaws.com", "rds.amazonaws.com",
              ]
            }
          }
        }
      ]
    })

    lambda_ecr_kms = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "lambda:CreateFunction", "lambda:DeleteFunction",
            "lambda:GetFunction*", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
            "lambda:PublishVersion", "lambda:ListVersionsByFunction",
            "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
            "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
            "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency",
            "lambda:InvokeFunction",
          ]
          Resource = "arn:aws:lambda:eu-west-2:*:function:myapp_*"
        },
        {
          Effect = "Allow"
          Action = [
            "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
            "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource",
            "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
            "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
            "ecr:PutImageTagMutability", "ecr:PutImageScanningConfiguration",
            "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
            "ecr:DescribeImages", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload", "ecr:PutImage",
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey"]
          Resource = "arn:aws:kms:eu-west-2:*:key/*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = [
                "lambda.eu-west-2.amazonaws.com",
                "secretsmanager.eu-west-2.amazonaws.com",
              ]
            }
          }
        }
      ]
    })

    apigw_dns_acm = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "apigateway:GET", "apigateway:POST", "apigateway:PUT",
            "apigateway:PATCH", "apigateway:DELETE",
            "apigateway:TagResource", "apigateway:UntagResource",
            "apigateway:UpdateRestApiPolicy",
          ]
          Resource = [
            "arn:aws:apigateway:eu-west-2::/restapis*",
            "arn:aws:apigateway:eu-west-2::/domainnames*",
            "arn:aws:apigateway:eu-west-2::/account",
            "arn:aws:apigateway:eu-west-2::/tags/*",
            "arn:aws:apigateway:eu-west-2::/usageplans*",
            "arn:aws:apigateway:eu-west-2::/apikeys*",
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "route53:GetHostedZone", "route53:ListHostedZones", "route53:ListHostedZonesByName",
            "route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets",
            "route53:GetChange", "route53:ChangeTagsForResource", "route53:ListTagsForResource",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "acm:RequestCertificate", "acm:DeleteCertificate", "acm:DescribeCertificate",
            "acm:ListCertificates", "acm:ListTagsForCertificate",
            "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate", "acm:GetCertificate",
          ]
          Resource = "*"
        }
      ]
    })

    rds_secrets = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "rds:CreateDBCluster", "rds:DeleteDBCluster", "rds:ModifyDBCluster",
            "rds:DescribeDBClusters",
            "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:ModifyDBInstance",
            "rds:DescribeDBInstances",
            "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:ModifyDBSubnetGroup",
            "rds:DescribeDBSubnetGroups",
            "rds:CreateDBClusterParameterGroup", "rds:ModifyDBClusterParameterGroup",
            "rds:DescribeDBClusterParameterGroups", "rds:DescribeDBClusterParameters",
            "rds:DeleteDBClusterParameterGroup",
            "rds:AddTagsToResource", "rds:RemoveTagsFromResource", "rds:ListTagsForResource",
            "rds:EnableHttpEndpoint", "rds:DisableHttpEndpoint",
            "rds:DescribeDBEngineVersions",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
            "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
            "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret",
            "secretsmanager:TagResource", "secretsmanager:UntagResource",
            "secretsmanager:ListSecrets",
            "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy",
            "secretsmanager:DeleteResourcePolicy",
          ]
          Resource = "arn:aws:secretsmanager:eu-west-2:*:secret:/*/myapp/*"
        }
      ]
    })

    s3 = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:CreateBucket", "s3:DeleteBucket",
            "s3:PutBucketTagging", "s3:GetBucketTagging",
            "s3:PutBucketAcl", "s3:GetBucketAcl",
            "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
            "s3:PutBucketVersioning", "s3:GetBucketVersioning",
            "s3:PutBucketLogging", "s3:GetBucketLogging",
            "s3:PutBucketNotification", "s3:GetBucketNotification",
            "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
            "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
            "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
            "s3:PutIntelligentTieringConfiguration", "s3:GetIntelligentTieringConfiguration",
            "s3:PutBucketCORS", "s3:GetBucketCORS",
            "s3:PutReplicationConfiguration", "s3:GetReplicationConfiguration",
            "s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket",
          ]
          Resource = [
            "arn:aws:s3:::myapp-*", "arn:aws:s3:::myapp-*/*",
            "arn:aws:s3:::myappingest-*", "arn:aws:s3:::myappingest-*/*",
          ]
        },
        {
          Effect = "Allow"
          Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
          Resource = [
            "arn:aws:s3:::lambda-upload-*", "arn:aws:s3:::lambda-upload-*/*",
          ]
        }
      ]
    })

    cognito = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "cognito-idp:CreateUserPool", "cognito-idp:DeleteUserPool",
            "cognito-idp:UpdateUserPool", "cognito-idp:DescribeUserPool",
            "cognito-idp:ListUserPools",
            "cognito-idp:CreateUserPoolDomain", "cognito-idp:DeleteUserPoolDomain",
            "cognito-idp:DescribeUserPoolDomain", "cognito-idp:UpdateUserPoolDomain",
            "cognito-idp:CreateUserPoolClient", "cognito-idp:DeleteUserPoolClient",
            "cognito-idp:UpdateUserPoolClient", "cognito-idp:DescribeUserPoolClient",
            "cognito-idp:ListUserPoolClients",
            "cognito-idp:CreateResourceServer", "cognito-idp:DeleteResourceServer",
            "cognito-idp:UpdateResourceServer", "cognito-idp:DescribeResourceServer",
            "cognito-idp:ListResourceServers",
            "cognito-idp:TagResource", "cognito-idp:UntagResource",
            "cognito-idp:ListTagsForResource",
            "cognito-idp:SetUserPoolMfaConfig", "cognito-idp:GetUserPoolMfaConfig",
          ]
          Resource = "*"
        }
      ]
    })

    bedrock = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "bedrock:CreateKnowledgeBase", "bedrock:DeleteKnowledgeBase",
            "bedrock:UpdateKnowledgeBase", "bedrock:GetKnowledgeBase",
            "bedrock:ListKnowledgeBases",
            "bedrock:CreateDataSource", "bedrock:DeleteDataSource",
            "bedrock:UpdateDataSource", "bedrock:GetDataSource",
            "bedrock:ListDataSources",
            "bedrock:TagResource", "bedrock:UntagResource", "bedrock:ListTagsForResource",
            "bedrock:ListFoundationModels", "bedrock:GetFoundationModel",
          ]
          Resource = "*"
        }
      ]
    })

    logs_events = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
            "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
            "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
            "logs:PutResourcePolicy", "logs:DescribeResourcePolicies",
          ]
          Resource = "arn:aws:logs:eu-west-2:*:log-group:/aws/*"
        },
        {
          Effect = "Allow"
          Action = [
            "events:PutRule", "events:DeleteRule", "events:DescribeRule", "events:ListRules",
            "events:PutTargets", "events:RemoveTargets", "events:ListTargetsByRule",
            "events:TagResource", "events:UntagResource", "events:ListTagsForResource",
          ]
          Resource = "arn:aws:events:eu-west-2:*:rule/*"
        }
      ]
    })
  }

  tags = local.tags
}
```

## Operational notes

* The OIDC provider is account-wide. Once it has been created (by the first project in the account
  setting `create_oidc_provider = true`) every subsequent project should leave the flag at `false`,
  and the data source in this module will look it up.
* Bedrock model access (the per-account "request access to model" step) is **not** Terraform-managed
  and therefore **not** covered by these permissions; it must be requested manually from the Bedrock
  console.
