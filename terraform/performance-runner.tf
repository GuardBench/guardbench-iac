# Dedicated, disposable execution host for the backend performance runner.
# The runner artifact is supplied independently through S3, so this host can
# later be replaced by a container runner without changing the artifact format.

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
      {
        Sid      = "ReadRunnerBootstrapArtifact"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.performance_results.arn}/performance/bootstrap/*"
      },
      {
        Sid      = "WritePerformanceResults"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.performance_results.arn}/performance/results/*"
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

# Invoke this document after a self-contained Runner artifact is published to
# performance/bootstrap/runner.tar.gz. The artifact supplies Python 3.11+, k6,
# psql, Java 21/Gradle, and backend runner code without requiring NAT access.
resource "aws_ssm_document" "performance_runner_bootstrap" {
  name            = "${var.project}-${var.environment}-performance-runner-bootstrap"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install a versioned GuardBench performance runner artifact from private S3"
    parameters = {
      ArtifactKey = {
        type        = "String"
        default     = "performance/bootstrap/runner.tar.gz"
        description = "S3 key for the self-contained performance runner artifact"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "installPerformanceRunner"
      inputs = {
        runCommand = [
          "set -euo pipefail",
          "install -d -m 0755 /opt/guardbench-performance-runner",
          "aws s3 cp s3://${aws_s3_bucket.performance_results.id}/{{ ArtifactKey }} /tmp/guardbench-performance-runner.tar.gz",
          "rm -rf /opt/guardbench-performance-runner/*",
          "tar -xzf /tmp/guardbench-performance-runner.tar.gz -C /opt/guardbench-performance-runner",
          "/opt/guardbench-performance-runner/bin/verify-runtime",
        ]
      }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-bootstrap"
    Purpose = "performance-testing"
  }
}
