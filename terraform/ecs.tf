data "aws_caller_identity" "current" {}

locals {
  selected_db = var.ecs_db_target == "performance" ? {
    address           = aws_db_instance.performance.address
    master_secret_arn = aws_db_instance.performance.master_user_secret[0].secret_arn
    } : {
    address           = aws_db_instance.app.address
    master_secret_arn = aws_db_instance.app.master_user_secret[0].secret_arn
  }
}

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

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}-${var.environment}/app"
  retention_in_days = 14
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-${var.environment}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_exec_secrets" {
  name = "${var.project}-${var.environment}-ecs-exec-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.selected_db.master_secret_arn
    }]
  })
}

resource "aws_iam_role" "app_task" {
  name = "${var.project}-${var.environment}-app-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app_task" {
  name = "${var.project}-${var.environment}-app-task-policy"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
        ]
        Resource = values(aws_sqs_queue.source)[*].arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:CreateGuardrailVersion",
          "bedrock:ApplyGuardrail",
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:guardrail/*"
      },
    ]
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-${var.environment}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_cpu
  memory                   = var.api_memory

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.app_task.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.api_container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "SERVER_PORT", value = tostring(var.api_container_port) },
      { name = "SPRING_DOCKER_COMPOSE_ENABLED", value = "false" },
      { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${local.selected_db.address}:${var.db_port}/guardbench?sslmode=require" },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "SQS_ENABLED", value = "true" },
      { name = "WORKER_ENABLED", value = "true" },
      { name = "SPRING_TASK_SCHEDULING_POOL_SIZE", value = "4" },
      { name = "GUARDBENCH_SQS_QUEUE_URLS_RESOLVE", value = aws_sqs_queue.source["gb-run-resolve"].url },
      { name = "GUARDBENCH_SQS_QUEUE_URLS_WORK_ITEMS", value = aws_sqs_queue.source["gb-workitems"].url },
      { name = "GUARDBENCH_SQS_QUEUE_URLS_RUN_FINALIZE", value = aws_sqs_queue.source["gb-run-finalize"].url },
    ]

    secrets = [
      { name = "SPRING_DATASOURCE_USERNAME", valueFrom = "${local.selected_db.master_secret_arn}:username::" },
      { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = "${local.selected_db.master_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project}-${var.environment}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_desired_count
  launch_type     = "FARGATE"

  # GitHub Actions owns application task-definition revisions after the
  # initial service creation. Terraform continues to own the service shape
  # but must not roll the service back to its baseline revision.
  lifecycle {
    ignore_changes = [task_definition]
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "app"
    container_port   = var.api_container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}
