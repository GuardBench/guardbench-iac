# ============================================
# Application Load Balancer (API 전용)
# ALB 기본 DNS로 접근 (guardbench-dev-alb-xxxx.ap-northeast-2.elb.amazonaws.com)
# Route 53 / 커스텀 도메인은 나중에 추가 가능
# ============================================

resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.environment == "prod" ? true : false

  tags = {
    Name = "${var.project}-${var.environment}-alb"
  }
}

# ============================================
# Target Group (API)
# ============================================

resource "aws_lb_target_group" "api" {
  name        = "${var.project}-${var.environment}-api-tg"
  port        = var.api_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project}-${var.environment}-api-tg"
  }
}

# ============================================
# Listener (HTTP)
# 도메인/인증서 확보 후 HTTPS 리스너 추가 예정
# ============================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
