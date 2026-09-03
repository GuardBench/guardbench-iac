# ============================================
# ALB Security Group
# ============================================
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "GuardBench ALB - public HTTPS ingress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-alb-sg"
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  description       = "HTTP from CloudFront origin-facing servers"
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_to_api" {
  type                     = "egress"
  from_port                = var.api_container_port
  to_port                  = var.api_container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  description              = "Forward to API service"
  security_group_id        = aws_security_group.alb.id
}

# ============================================
# API Service Security Group (ECS Fargate)
# ============================================
resource "aws_security_group" "api" {
  name        = "${var.project}-${var.environment}-api-sg"
  description = "GuardBench API Fargate service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-api-sg"
  }
}

resource "aws_security_group_rule" "api_ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.api_container_port
  to_port                  = var.api_container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "From ALB"
  security_group_id        = aws_security_group.api.id
}

resource "aws_security_group_rule" "api_egress_to_vpc_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoints.id
  description              = "AWS services through VPC endpoints"
  security_group_id        = aws_security_group.api.id
}

# The API calls external AI providers through the private subnet NAT Gateway.
# Keep tasks private; allow only outbound HTTPS to the provider endpoint.
resource "aws_security_group_rule" "api_egress_to_external_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "External HTTPS endpoints via NAT Gateway"
  security_group_id = aws_security_group.api.id
}

# ECR image layer downloads use the S3 Gateway endpoint rather than an
# interface endpoint ENI. Restrict the task egress to the endpoint's managed
# S3 prefix list; no internet or NAT route is required.
resource "aws_security_group_rule" "api_egress_to_s3_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
  description       = "ECR image layers through S3 Gateway endpoint"
  security_group_id = aws_security_group.api.id
}

resource "aws_security_group_rule" "api_egress_to_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  description              = "To RDS PostgreSQL"
  security_group_id        = aws_security_group.api.id
}

resource "aws_security_group_rule" "api_egress_to_performance_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_rds.id
  description              = "To performance-test RDS PostgreSQL"
  security_group_id        = aws_security_group.api.id
}

resource "aws_security_group_rule" "api_egress_to_performance_alb" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_api_alb.id
  description              = "Performance Backend target calls through the internal ALB"
  security_group_id        = aws_security_group.api.id
}

# ============================================
# Worker Security Group (Orchestrator + Executor)
# ============================================
resource "aws_security_group" "worker" {
  name        = "${var.project}-${var.environment}-worker-sg"
  description = "GuardBench Orchestrator/Executor Fargate (SQS polling)"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-worker-sg"
  }
}

# Worker는 인바운드 없음 - SQS 폴링 방식

resource "aws_security_group_rule" "worker_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "AWS services (Bedrock, SQS, CloudWatch, SSM)"
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_egress_to_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  description              = "To RDS PostgreSQL"
  security_group_id        = aws_security_group.worker.id
}

# ============================================
# RDS Security Group
# ============================================
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "GuardBench RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-rds-sg"
  }
}

resource "aws_security_group_rule" "rds_ingress_from_api" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  description              = "From API service"
  security_group_id        = aws_security_group.rds.id
}

# ============================================
# Performance RDS Security Group
# ============================================
resource "aws_security_group" "performance_rds" {
  name        = "${var.project}-${var.environment}-performance-rds-sg"
  description = "GuardBench performance-test RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.environment}-performance-rds-sg"
    Purpose = "performance-testing"
  }
}

resource "aws_security_group_rule" "performance_rds_ingress_from_api" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  description              = "From Backend ECS services"
  security_group_id        = aws_security_group.performance_rds.id
}

resource "aws_security_group_rule" "api_ingress_from_performance_alb" {
  type                     = "ingress"
  from_port                = var.api_container_port
  to_port                  = var.api_container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_api_alb.id
  description              = "From internal performance API ALB"
  security_group_id        = aws_security_group.api.id
}

# ============================================
# Demo AI Service Security Group (ECS Fargate)
# ============================================
resource "aws_security_group" "demo_ai" {
  name        = "${var.project}-${var.environment}-demo-ai-sg"
  description = "GuardBench Demo AI performance-test Fargate service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.environment}-demo-ai-sg"
    Purpose = "performance-testing"
  }
}

resource "aws_security_group_rule" "demo_ai_ingress_from_performance_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_api_alb.id
  description              = "Demo AI requests from the private performance ALB"
  security_group_id        = aws_security_group.demo_ai.id
}

resource "aws_security_group_rule" "demo_ai_egress_to_vpc_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoints.id
  description              = "Bedrock, ECR, and CloudWatch through VPC endpoints"
  security_group_id        = aws_security_group.demo_ai.id
}

resource "aws_security_group_rule" "demo_ai_egress_to_s3_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
  description       = "ECR image layers through S3 Gateway endpoint"
  security_group_id = aws_security_group.demo_ai.id
}

# ============================================
# Performance Runner Security Group
# ============================================
resource "aws_security_group" "performance_runner" {
  name        = "${var.project}-${var.environment}-performance-runner-sg"
  description = "GuardBench EC2 performance-test runner; no inbound access"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-sg"
    Purpose = "performance-testing"
  }
}

resource "aws_security_group_rule" "performance_runner_egress_to_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_rds.id
  description              = "Reset and migrate performance-test RDS"
  security_group_id        = aws_security_group.performance_runner.id
}

resource "aws_security_group_rule" "performance_runner_egress_to_vpc_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoints.id
  description              = "AWS APIs through VPC endpoints"
  security_group_id        = aws_security_group.performance_runner.id
}

# The internal performance ALB is the approved in-VPC API path for the runner.
# It avoids a NAT gateway and never exposes the API through an external CIDR.
resource "aws_security_group_rule" "performance_runner_egress_to_alb" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_api_alb.id
  description              = "Call GuardBench API through the private ALB"
  security_group_id        = aws_security_group.performance_runner.id
}

resource "aws_security_group_rule" "performance_runner_egress_to_s3_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
  description       = "ECR image layers and performance results through S3 Gateway endpoint"
  security_group_id = aws_security_group.performance_runner.id
}


resource "aws_security_group_rule" "performance_rds_ingress_from_runner" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_runner.id
  description              = "From dedicated performance-test runner"
  security_group_id        = aws_security_group.performance_rds.id
}

# ============================================
# VPC Endpoints Security Group
# ============================================
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpce-sg"
  description = "GuardBench VPC Endpoints - allow HTTPS from private subnets"
  vpc_id      = aws_vpc.main.id

  # Existing state owns this inline ingress. Allow the private application
  # services, the dedicated performance runner, and the RDS access host.
  ingress {
    description = "HTTPS from the combined app service"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.api.id,
      aws_security_group.performance_runner.id,
      aws_security_group.demo_ai.id,
      aws_security_group.db_access.id,
    ]
  }

  tags = {
    Name = "${var.project}-${var.environment}-vpce-sg"
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}
