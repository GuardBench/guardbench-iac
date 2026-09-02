# OpenAI-compatible Demo AI target for integrated performance tests.
# This service deliberately has its own task definition, service, task role,
# execution role, log group, and security group. It reuses the existing dev
# ECS cluster and private subnets but never becomes a backend sidecar.

locals {
  demo_ai_container_port = 8080
}

resource "aws_cloudwatch_log_group" "demo_ai" {
  name              = "/ecs/${var.project}-${var.environment}/demo-ai"
  retention_in_days = 14

  tags = {
    Name    = "/ecs/${var.project}-${var.environment}/demo-ai"
    Purpose = "performance-testing"
  }
}

resource "aws_iam_role" "demo_ai_task_execution" {
  name = "${var.project}-${var.environment}-demo-ai-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-demo-ai-exec-role"
    Purpose = "performance-testing"
  }
}

resource "aws_iam_role_policy_attachment" "demo_ai_task_execution" {
  role       = aws_iam_role.demo_ai_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "demo_ai_task" {
  name = "${var.project}-${var.environment}-demo-ai-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-demo-ai-task-role"
    Purpose = "performance-testing"
  }
}

resource "aws_iam_role_policy" "demo_ai_task" {
  name = "${var.project}-${var.environment}-demo-ai-task-policy"
  role = aws_iam_role.demo_ai_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeApprovedBedrockModels"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = var.demo_ai_bedrock_resource_arns
    }]
  })
}

resource "aws_ecs_task_definition" "demo_ai" {
  family                   = "${var.project}-${var.environment}-demo-ai"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.demo_ai_cpu
  memory                   = var.demo_ai_memory

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  execution_role_arn = aws_iam_role.demo_ai_task_execution.arn
  task_role_arn      = aws_iam_role.demo_ai_task.arn

  container_definitions = jsonencode([{
    name      = "demo-ai"
    image     = "${aws_ecr_repository.demo_ai.repository_url}:${var.demo_ai_image_tag}"
    essential = true

    portMappings = [{
      containerPort = local.demo_ai_container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "BEDROCK_MODEL_ID", value = var.demo_ai_bedrock_model_id },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.demo_ai.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "demo-ai"
      }
    }
  }])
}

resource "aws_ecs_service" "demo_ai" {
  name            = "${var.project}-${var.environment}-demo-ai"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.demo_ai.arn
  desired_count   = var.demo_ai_enabled ? var.demo_ai_desired_count : 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.demo_ai.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.performance_demo_ai.arn
    container_name   = "demo-ai"
    container_port   = local.demo_ai_container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.performance_api,
    aws_lb_listener_rule.performance_demo_ai,
    aws_iam_role_policy_attachment.demo_ai_task_execution,
  ]
}
