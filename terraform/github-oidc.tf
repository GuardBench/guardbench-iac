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

  backend_task_definition_family_arn             = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project}-${var.environment}-app:*"
  backend_performance_task_definition_family_arn = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project}-${var.environment}-performance-app:*"
  backend_ecs_service_arn                        = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  backend_performance_ecs_service_arn            = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main.name}/${aws_ecs_service.performance_app.name}"
}

data "aws_partition" "current" {}

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

data "aws_iam_policy_document" "backend_github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsDevEnvironment"
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
      # Environment subjects do not contain a branch. Restrict the GitHub
      # dev environment's deployment branches/tags in repository settings.
      values = [
        "repo:GuardBench@316853045/guardbench-backend@1333885107:environment:dev",
      ]
    }
  }
}

resource "aws_iam_role" "backend_github_actions_deploy" {
  name               = "${var.project}-${var.environment}-backend-github-deploy"
  description        = "Deploy GuardBench dev backend from GitHub Actions via OIDC"
  assume_role_policy = data.aws_iam_policy_document.backend_github_actions_assume_role.json

  max_session_duration = 3600

  tags = {
    Name = "${var.project}-${var.environment}-backend-github-deploy"
  }
}

data "aws_iam_policy_document" "backend_github_actions_deploy" {
  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushBackendImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid     = "DescribeTaskDefinition"
    effect  = "Allow"
    actions = ["ecs:DescribeTaskDefinition"]
    # ECS does not support resource-level permissions for this action.
    resources = ["*"]
  }

  statement {
    sid       = "RegisterAppTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = [local.backend_task_definition_family_arn]
  }

  statement {
    sid       = "DescribeAppService"
    effect    = "Allow"
    actions   = ["ecs:DescribeServices"]
    resources = [local.backend_ecs_service_arn]
  }

  statement {
    sid       = "UpdateAppService"
    effect    = "Allow"
    actions   = ["ecs:UpdateService"]
    resources = [local.backend_ecs_service_arn]

    condition {
      test     = "ArnLike"
      variable = "ecs:task-definition"
      values   = [local.backend_task_definition_family_arn]
    }
  }

  statement {
    sid       = "PassEcsTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.app_task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "backend_github_actions_deploy" {
  name   = "${var.project}-${var.environment}-backend-deploy"
  role   = aws_iam_role.backend_github_actions_deploy.id
  policy = data.aws_iam_policy_document.backend_github_actions_deploy.json
}

data "aws_iam_policy_document" "backend_performance_github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsPerformanceEnvironment"
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
      # and repository IDs. The performance Environment is branch-restricted
      # to dev in GitHub settings, so the environment subject is sufficient.
      values = [
        "repo:GuardBench@316853045/guardbench-backend@1333885107:environment:performance",
      ]
    }
  }
}

resource "aws_iam_role" "backend_performance_github_actions_deploy" {
  name               = "${var.project}-${var.environment}-performance-backend-deploy"
  description        = "Deploy GuardBench performance backend from GitHub Actions performance environment"
  assume_role_policy = data.aws_iam_policy_document.backend_performance_github_actions_assume_role.json

  max_session_duration = 3600

  tags = {
    Name    = "${var.project}-${var.environment}-performance-backend-deploy"
    Purpose = "performance-testing"
  }
}

data "aws_iam_policy_document" "backend_performance_github_actions_deploy" {
  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushPerformanceBackendImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "DescribeTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "RegisterPerformanceTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = [local.backend_performance_task_definition_family_arn]
  }

  statement {
    sid       = "DescribePerformanceService"
    effect    = "Allow"
    actions   = ["ecs:DescribeServices"]
    resources = [local.backend_performance_ecs_service_arn]
  }

  statement {
    sid       = "UpdatePerformanceService"
    effect    = "Allow"
    actions   = ["ecs:UpdateService"]
    resources = [local.backend_performance_ecs_service_arn]

    condition {
      test     = "ArnLike"
      variable = "ecs:task-definition"
      values   = [local.backend_performance_task_definition_family_arn]
    }
  }

  statement {
    sid       = "PassEcsTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.app_task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "backend_performance_github_actions_deploy" {
  name   = "${var.project}-${var.environment}-performance-backend-deploy"
  role   = aws_iam_role.backend_performance_github_actions_deploy.id
  policy = data.aws_iam_policy_document.backend_performance_github_actions_deploy.json
}
