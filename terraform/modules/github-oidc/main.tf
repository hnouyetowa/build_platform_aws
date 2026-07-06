locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "cicd"
    },
    var.tags,
  )

  # OIDC subject: restricts the trust to a single repo + branch.
  # Format: repo:{org}/{repo}:ref:refs/heads/{branch}
  # This means only the app repo's main branch can assume this role — not PRs, forks, or other branches.
  oidc_subject = "repo:${var.github_org}/${var.app_repo_name}:ref:refs/heads/${var.branch}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── GitHub Actions OIDC Provider ──────────────────────────────────────────────
# One OIDC provider per AWS account (not per environment). The thumbprints below
# cover both the current and previous GitHub Actions certificate chains.
# If the provider already exists (create_oidc_provider = false), import it with:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::{account}:oidc-provider/token.actions.githubusercontent.com

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",  # GitHub root CA (primary)
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",  # GitHub root CA (secondary, post-2023)
  ]

  tags = merge(local.common_tags, {
    Name = "github-actions-oidc-provider"
  })
}

# Look up an existing OIDC provider when create_oidc_provider = false
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

# ── GitHub Actions IAM Role ───────────────────────────────────────────────────
# Scoped to a single application repo + branch. Any other source (PRs, other
# branches, other repos) cannot assume this role.

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Restrict to the audience GitHub tokens send
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to a single repo + branch — prevents any other source from using this role
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.oidc_subject]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions-role"
  description        = "Assumed by GitHub Actions CI in ${var.github_org}/${var.app_repo_name} (${var.branch} branch) via OIDC"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-github-actions-role"
    GitHubOrg = var.github_org
    AppRepo   = var.app_repo_name
  })
}

# ── ECR Push Permissions ──────────────────────────────────────────────────────
# ecr:GetAuthorizationToken is account-level and must use resource "*".
# All other actions are scoped to petclinic-{env}/* ECR repositories only.

data "aws_iam_policy_document" "ecr_push" {
  # Auth token — account-level, cannot be scoped to specific repos
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push permissions — scoped to petclinic-{env}/* repos only
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}/*",
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${local.name_prefix}-ecr-push-policy"
  description = "Allows GitHub Actions CI to push images to petclinic-${var.environment}/* ECR repositories"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-push-policy"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
