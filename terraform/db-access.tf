# Private SSM access host for developer-to-RDS port forwarding.
# The host has no public IP or inbound rule; all operator access goes through
# AWS Systems Manager Session Manager and the existing private endpoints.

data "aws_ssm_parameter" "db_access_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "db_access" {
  name        = "${var.project}-${var.environment}-db-access-sg"
  description = "SSM-only private host for RDS port forwarding"
  vpc_id      = aws_vpc.main.id
  ingress     = []

  # Egress is managed by the dedicated aws_security_group_rule resources below.
  # Ignore the provider's default egress representation to avoid mixing inline
  # and standalone ownership during refresh.
  egress = []
  lifecycle {
    ignore_changes = [egress]
  }

  tags = {
    Name    = "${var.project}-${var.environment}-db-access-sg"
    Purpose = "rds-access"
  }
}

resource "aws_security_group_rule" "db_access_egress_to_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  description              = "Port forwarding to development RDS"
  security_group_id        = aws_security_group.db_access.id
}

resource "aws_security_group_rule" "db_access_egress_to_performance_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.performance_rds.id
  description              = "Port forwarding to performance RDS"
  security_group_id        = aws_security_group.db_access.id
}

resource "aws_security_group_rule" "db_access_egress_to_vpc_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoints.id
  description              = "SSM APIs through VPC endpoints"
  security_group_id        = aws_security_group.db_access.id
}

resource "aws_security_group_rule" "rds_ingress_from_db_access" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db_access.id
  description              = "Developer access through SSM port forwarding"
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group_rule" "performance_rds_ingress_from_db_access" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db_access.id
  description              = "Developer access through SSM port forwarding"
  security_group_id        = aws_security_group.performance_rds.id
}

resource "aws_iam_role" "db_access" {
  name = "${var.project}-${var.environment}-db-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-db-access-role"
    Purpose = "rds-access"
  }
}

resource "aws_iam_role_policy_attachment" "db_access_ssm" {
  role       = aws_iam_role.db_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "db_access" {
  name = "${var.project}-${var.environment}-db-access-profile"
  role = aws_iam_role.db_access.name
}

resource "aws_instance" "db_access" {
  count                       = var.db_access_host_enabled ? 1 : 0
  ami                         = data.aws_ssm_parameter.db_access_ami.value
  instance_type               = var.db_access_host_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.db_access.id]
  iam_instance_profile        = aws_iam_instance_profile.db_access.name
  associate_public_ip_address = false

  user_data = replace(<<-USERDATA
    #!/bin/bash
    set -euo pipefail
    systemctl enable --now amazon-ssm-agent || true
  USERDATA
  , "\r\n", "\n")

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name    = "${var.project}-${var.environment}-db-access"
    Purpose = "rds-access"
  }

  depends_on = [
    aws_iam_role_policy_attachment.db_access_ssm,
    aws_security_group_rule.db_access_egress_to_vpc_endpoints,
  ]
}
