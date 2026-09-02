# The public ALB has no private-subnet route without NAT. This internal ALB is
# therefore the explicit, SG-scoped PERF_BASE_URL path for the Spot runner.
resource "aws_security_group" "performance_api_alb" {
  name        = "${var.project}-${var.environment}-performance-api-alb-sg"
  description = "Internal ALB that exposes GuardBench API only to the performance runner"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.environment}-performance-api-alb-sg"
    Purpose = "performance-testing"
  }
}

resource "aws_security_group_rule" "performance_api_alb_ingress_from_runner" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_runner.id
  description              = "GuardBench performance runner API requests"
  security_group_id        = aws_security_group.performance_api_alb.id
}

resource "aws_security_group_rule" "performance_api_alb_egress_to_api" {
  type                     = "egress"
  from_port                = var.api_container_port
  to_port                  = var.api_container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  description              = "Forward performance runner API requests to ECS"
  security_group_id        = aws_security_group.performance_api_alb.id
}

resource "aws_lb" "performance_api" {
  name               = "${var.project}-${var.environment}-performance-api"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.performance_api_alb.id]
  subnets            = aws_subnet.private[*].id

  tags = {
    Name    = "${var.project}-${var.environment}-performance-api"
    Purpose = "performance-testing"
  }
}

resource "aws_lb_target_group" "performance_api" {
  name        = "${var.project}-${var.environment}-performance-api"
  port        = var.api_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/api/v1/test-suites"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name    = "${var.project}-${var.environment}-performance-api"
    Purpose = "performance-testing"
  }
}

resource "aws_lb_listener" "performance_api" {
  load_balancer_arn = aws_lb.performance_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.performance_api.arn
  }
}
