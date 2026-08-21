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

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS from internet"
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP from internet (redirects to HTTPS)"
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

resource "aws_security_group_rule" "api_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "AWS services (SQS, CloudWatch, SSM)"
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

resource "aws_security_group_rule" "rds_ingress_from_worker" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  description              = "From Worker services"
  security_group_id        = aws_security_group.rds.id
}

# ============================================
# VPC Endpoints Security Group
# ============================================
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpce-sg"
  description = "GuardBench VPC Endpoints - allow HTTPS from private subnets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from API and Worker services"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id, aws_security_group.worker.id]
  }

  tags = {
    Name = "${var.project}-${var.environment}-vpce-sg"
  }
}
