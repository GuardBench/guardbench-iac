# ============================================
# ECR Repository (컨테이너 이미지 저장소)
# 단일 App Service가 HTTP API와 비동기 worker를 함께 실행한다.
# ============================================

resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-ecr"
  }
}

# 오래된 이미지 자동 정리 (최근 10개만 유지)
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Dedicated repository for the Dockerized performance runner. Keep it separate
# from the application repository because both images use the backend commit
# SHA as an immutable tag.
resource "aws_ecr_repository" "performance_runner" {
  name                 = "${var.project}-${var.environment}-performance-runner"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-ecr"
    Purpose = "performance-testing"
  }
}

resource "aws_ecr_lifecycle_policy" "performance_runner" {
  repository = aws_ecr_repository.performance_runner.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last 10 performance runner images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Preserve the existing Demo AI image repository that is already managed in
# the shared state. It is not part of the application deployment, but omitting
# an existing state address would make Terraform plan its deletion.
resource "aws_ecr_repository" "demo_ai" {
  name                 = "guardbench-demo-ai-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "guardbench-demo-ai-service-ecr"
    Purpose = "performance-testing"
  }
}

resource "aws_ecr_lifecycle_policy" "demo_ai" {
  repository = aws_ecr_repository.demo_ai.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last 10 Demo AI images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
