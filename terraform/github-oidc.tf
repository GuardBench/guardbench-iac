# GitHub Actions OIDC provider is account-wide. Reuse an existing provider by
# setting github_oidc_provider_arn; otherwise this stack creates it.
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.github_oidc_provider_arn == null ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

locals {
  github_oidc_provider_arn = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github_actions[0].arn
}

data "aws_iam_policy_document" "frontend_github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsMainBranch"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # GuardBench customizes GitHub OIDC subjects with immutable organization
      # and repository IDs. Keep the main ref suffix to restrict deployments.
      values = [
        "repo:GuardBench@316853045/guardbench-frontend@1346059955:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "frontend_github_actions_deploy" {
  name               = "${var.project}-${var.environment}-frontend-github-deploy"
  description        = "Deploy GuardBench dev frontend from GitHub Actions main branch"
  assume_role_policy = data.aws_iam_policy_document.frontend_github_actions_assume_role.json

  max_session_duration = 3600

  tags = {
    Name = "${var.project}-${var.environment}-frontend-github-deploy"
  }
}

data "aws_iam_policy_document" "frontend_github_actions_deploy" {
  statement {
    sid = "ReadFrontendBucket"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.frontend.arn]
  }

  statement {
    sid = "SyncFrontendObjects"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  statement {
    sid       = "InvalidateFrontendDistribution"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_role_policy" "frontend_github_actions_deploy" {
  name   = "${var.project}-${var.environment}-frontend-deploy"
  role   = aws_iam_role.frontend_github_actions_deploy.id
  policy = data.aws_iam_policy_document.frontend_github_actions_deploy.json
}
