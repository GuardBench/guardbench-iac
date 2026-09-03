# Dedicated, disposable execution host for the backend performance runner.
# The host pulls a versioned Docker image from the private ECR repository.

data "aws_ssm_parameter" "performance_runner_ami" {
  # ECS Optimized AL2023 includes Docker and avoids package downloads from a
  # private subnet without NAT. The host uses Docker directly, not ECS.
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
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
        Sid    = "PullPerformanceRunnerImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = aws_ecr_repository.performance_runner.arn
      },
      {
        Sid      = "AuthorizeEcrPull"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ReadPerformanceQueueMetrics"
        Effect = "Allow"
        Action = ["sqs:GetQueueAttributes"]
        Resource = concat(
          [for queue in values(aws_sqs_queue.source) : queue.arn],
          [for queue in values(aws_sqs_queue.dead_letter) : queue.arn],
          [for queue in values(aws_sqs_queue.performance_source) : queue.arn],
          [for queue in values(aws_sqs_queue.performance_dead_letter) : queue.arn],
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
  count                       = var.performance_runner_enabled ? 1 : 0
  ami                         = data.aws_ssm_parameter.performance_runner_ami.value
  instance_type               = var.performance_runner_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.performance_runner.id]
  iam_instance_profile        = aws_iam_instance_profile.performance_runner.name
  associate_public_ip_address = false

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    systemctl enable --now docker
    usermod -aG docker ec2-user || true
  USERDATA

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

# Invoke this document after an immutable Runner image is pushed to the
# dedicated private ECR repository. The image supplies Python 3.11+, k6, psql,
# Java 21/Gradle, and backend runner code without requiring NAT access.
resource "aws_ssm_document" "performance_runner_bootstrap" {
  name            = "${var.project}-${var.environment}-performance-runner-bootstrap"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Pull and verify a versioned GuardBench performance runner image from private ECR"
    parameters = {
      RunnerImage = {
        type        = "String"
        description = "Full immutable ECR image URI for the performance runner"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "preparePerformanceRunner"
      inputs = {
        runCommand = [
          "set -euo pipefail",
          "performance_base_url='http://${aws_lb.performance_api.dns_name}'",
          "curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \"$performance_base_url/health\" >/dev/null",
          "curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \"$performance_base_url/api/v1/test-suites?page=1&size=1\" >/dev/null",
          "runner_image='{{ RunnerImage }}'",
          "case \"$runner_image\" in \"${aws_ecr_repository.performance_runner.repository_url}:\"*) ;; *) echo 'RunnerImage must use the dedicated performance-runner ECR repository.' >&2; exit 1 ;; esac",
          "registry=\"$${runner_image%%/*}\"",
          "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin \"$registry\"",
          "docker pull \"$runner_image\"",
          "crlf_files=\"$(docker run --rm --entrypoint python3.11 \"$runner_image\" -c 'from pathlib import Path; print(\"\\n\".join(str(path) for path in Path(\"/workspace/bin\").rglob(\"*\") if path.is_file() and b\"\\r\\n\" in path.read_bytes()))')\"",
          "if [ -n \"$crlf_files\" ]; then echo \"Runner image contains CRLF scripts: $crlf_files\" >&2; echo 'Rebuild and republish the image from an LF-preserving checkout.' >&2; exit 1; fi",
          "docker run --rm --entrypoint /workspace/bin/verify-runtime \"$runner_image\"",
          "install -d -m 0755 /opt/guardbench-performance-runner",
          "printf '%s\\n' \"$runner_image\" > /opt/guardbench-performance-runner/image",
        ]
      }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-bootstrap"
    Purpose = "performance-testing"
  }
}
