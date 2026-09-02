# Dedicated, disposable execution host for the backend performance runner.
# Runner software is intentionally not installed here: the host only provides
# private-network access, SSM operations access, and least-privilege AWS APIs.

data "aws_ssm_parameter" "performance_runner_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "performance_runner" {
  name = "${var.project}-${var.environment}-performance-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-role"
    Purpose = "performance-testing"
  }
}

resource "aws_iam_role_policy_attachment" "performance_runner_ssm" {
  role       = aws_iam_role.performance_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "performance_runner" {
  name = "${var.project}-${var.environment}-performance-runner-policy"
  role = aws_iam_role.performance_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPerformanceQueueMetrics"
        Effect = "Allow"
        Action = ["sqs:GetQueueAttributes"]
        Resource = concat(
          [for queue in values(aws_sqs_queue.source) : queue.arn],
          [for queue in values(aws_sqs_queue.dead_letter) : queue.arn],
        )
      },
      {
        Sid      = "ReadCloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData"]
        Resource = "*"
      },
      {
        Sid      = "ReadPerformanceDatabaseCredentials"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_db_instance.performance.master_user_secret[0].secret_arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "performance_runner" {
  name = "${var.project}-${var.environment}-performance-runner-profile"
  role = aws_iam_role.performance_runner.name
}

resource "aws_instance" "performance_runner" {
  ami                         = data.aws_ssm_parameter.performance_runner_ami.value
  instance_type               = var.performance_runner_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.performance_runner.id]
  iam_instance_profile        = aws_iam_instance_profile.performance_runner.name
  associate_public_ip_address = false

  dynamic "instance_market_options" {
    for_each = var.performance_runner_spot ? [1] : []

    content {
      market_type = "spot"

      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.performance_runner_root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner"
    Purpose = "performance-testing"
  }

  depends_on = [aws_iam_role_policy_attachment.performance_runner_ssm]
}
