# ============================================
# ECS Cluster + API Service + Worker Services
# api: ALB 뒤에서 REST 서빙
# orchestrator: SQS 폴링 (gb-run-resolve, gb-run-finalize)
# executor: SQS 폴링 (gb-workitems)
# ============================================

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project}-${var.environment}-cluster"
  }
}

# --- CloudWatch Log Groups ---
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project}-${var.environment}/api"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/ecs/${var.project}-${var.environment}/orchestrator"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "executor" {
  name              = "/ecs/${var.project}-${var.environment}/executor"
  retention_in_days = 30
}

# --- IAM: Task Execution Role (이미지 pull, 로그, SSM 읽기) ---
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-${var.environment}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_exec_ssm" {
  name = "${var.project}-${var.environment}-ecs-exec-ssm"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project}/${var.environment}/*"
    }]
  })
}

# --- IAM: API Task Role ---
resource "aws_iam_role" "api_task" {
  name = "${var.project}-${var.environment}-api-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "api_task" {
  name = "${var.project}-${var.environment}-api-task-policy"
  role = aws_iam_role.api_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "*"
      }
    ]
  })
}

# --- IAM: Worker Task Role (orchestrator + executor) ---
resource "aws_iam_role" "worker_task" {
  name = "${var.project}-${var.environment}-worker-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "worker_task" {
  name = "${var.project}-${var.environment}-worker-task-policy"
  role = aws_iam_role.worker_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ApplyGuardrail",
          "bedrock:GetGuardrail",
          "bedrock:CreateGuardrailVersion"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================
# Task Definitions
# ============================================

# API Task Definition
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-${var.environment}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.api_task.arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = var.api_container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "SERVICE_ROLE", value = "api" },
      { name = "SERVER_PORT", value = tostring(var.api_container_port) },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "api"
      }
    }
  }])
}

# Orchestrator Task Definition
resource "aws_ecs_task_definition" "orchestrator" {
  family                   = "${var.project}-${var.environment}-orchestrator"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn

  container_definitions = jsonencode([{
    name      = "orchestrator"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true

    environment = [
      { name = "SERVICE_ROLE", value = "orchestrator" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.orchestrator.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "orchestrator"
      }
    }
  }])
}

# Executor Task Definition
resource "aws_ecs_task_definition" "executor" {
  family                   = "${var.project}-${var.environment}-executor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn

  container_definitions = jsonencode([{
    name      = "executor"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true

    environment = [
      { name = "SERVICE_ROLE", value = "executor" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.executor.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "executor"
      }
    }
  }])
}

# ============================================
# ECS Services
# ============================================

# API Service (ALB 연결)
resource "aws_ecs_service" "api" {
  name            = "${var.project}-${var.environment}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.api_container_port
  }

  deployment_configuration {
    minimum_healthy_percent = 50
    maximum_percent         = 200
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# Orchestrator Service (SQS 폴링, ALB 없음)
resource "aws_ecs_service" "orchestrator" {
  name            = "${var.project}-${var.environment}-orchestrator"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.orchestrator.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# Executor Service (SQS 폴링, ALB 없음)
resource "aws_ecs_service" "executor" {
  name            = "${var.project}-${var.environment}-executor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.executor.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
