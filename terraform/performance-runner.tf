# Dedicated, disposable execution host for the backend performance runner.
# The host pulls a versioned Docker image from the private ECR repository.
locals {
  performance_runner_image_uri = var.performance_runner_image_tag == null ? null : "${aws_ecr_repository.performance_runner.repository_url}:${var.performance_runner_image_tag}"
  performance_runner_source_queue_urls = join(",", [
    aws_sqs_queue.performance_source["gb-run-resolve"].url,
    aws_sqs_queue.performance_source["gb-workitems"].url,
    aws_sqs_queue.performance_source["gb-run-finalize"].url,
  ])
  performance_runner_dlq_urls = join(",", [
    aws_sqs_queue.performance_dead_letter["gb-run-resolve"].url,
    aws_sqs_queue.performance_dead_letter["gb-workitems"].url,
    aws_sqs_queue.performance_dead_letter["gb-run-finalize"].url,
  ])

  performance_runner_source_queue_names = {
    resolve    = aws_sqs_queue.performance_source["gb-run-resolve"].name
    work_items = aws_sqs_queue.performance_source["gb-workitems"].name
    finalize   = aws_sqs_queue.performance_source["gb-run-finalize"].name
  }
  performance_runner_dlq_names = {
    resolve    = aws_sqs_queue.performance_dead_letter["gb-run-resolve"].name
    work_items = aws_sqs_queue.performance_dead_letter["gb-workitems"].name
    finalize   = aws_sqs_queue.performance_dead_letter["gb-run-finalize"].name
  }

}

data "aws_ssm_parameter" "performance_runner_ami" {
  # ECS Optimized AL2023 includes Docker and avoids package downloads from a
  # private subnet without NAT. The host uses Docker directly, not ECS.
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

data "aws_ecr_image" "performance_runner" {
  count = var.performance_runner_enabled && var.performance_runner_image_tag != null ? 1 : 0

  repository_name = aws_ecr_repository.performance_runner.name
  image_tag       = var.performance_runner_image_tag
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
          "expected_runner_image=\"${local.performance_runner_image_uri == null ? "" : local.performance_runner_image_uri}\"",
          "if [ -z \"$expected_runner_image\" ]; then echo \"performance_runner_image_tag must be configured before bootstrap.\" >&2; exit 1; fi",
          "if [ \"$runner_image\" != \"$expected_runner_image\" ]; then echo \"RunnerImage must match the Terraform-verified image: $expected_runner_image\" >&2; exit 1; fi",
          "case \"$runner_image\" in \"${aws_ecr_repository.performance_runner.repository_url}:\"*) ;; *) echo 'RunnerImage must use the dedicated performance-runner ECR repository.' >&2; exit 1 ;; esac",
          "registry=\"$${runner_image%%/*}\"",
          "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin \"$registry\"",
          "docker pull \"$runner_image\"",
          "image_digest=\"$(docker image inspect --format '{{index .RepoDigests 0}}' \"$runner_image\")\"",
          "case \"$image_digest\" in *@sha256:*) ;; *) echo 'Runner image digest could not be resolved after pull.' >&2; exit 1 ;; esac",

          "crlf_files=\"$(docker run --rm --entrypoint python3.11 \"$runner_image\" -c 'from pathlib import Path; print(\"\\n\".join(str(path) for path in Path(\"/workspace/bin\").rglob(\"*\") if path.is_file() and b\"\\r\\n\" in path.read_bytes()))')\"",
          "if [ -n \"$crlf_files\" ]; then echo \"Runner image contains CRLF scripts: $crlf_files\" >&2; echo 'Rebuild and republish the image from an LF-preserving checkout.' >&2; exit 1; fi",
          "docker run --rm --entrypoint /workspace/bin/verify-runtime \"$runner_image\"",

          "install -d -m 0755 /opt/guardbench-performance-runner",

          "environment_file=/opt/guardbench-performance-runner/environment",
          ": > \"$environment_file\"",
          "printf \"%s\\n\" \"AWS_REGION=${var.aws_region}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"INFRA_REVISION=${var.performance_runner_infra_revision}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_BASE_URL=http://${aws_lb.performance_api.dns_name}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_TARGET_URL=http://${aws_lb.performance_api.dns_name}/v1/chat/completions\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_TARGET_MODEL=demo-model\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_TARGET_REVISION=${var.demo_ai_image_tag}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_ECS_CLUSTER=${aws_ecs_cluster.main.name}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_ECS_SERVICE=${aws_ecs_service.performance_app.name}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_RDS_INSTANCE_ID=${aws_db_instance.performance.identifier}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SAGEMAKER_ENDPOINT_NAME=${local.sagemaker_classifier_endpoint_name}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SAGEMAKER_VARIANT_NAME=AllTraffic\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SOURCE_QUEUE_URLS=${local.performance_runner_source_queue_urls}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_DLQ_URLS=${local.performance_runner_dlq_urls}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SOURCE_QUEUE_RESOLVE_NAME=${local.performance_runner_source_queue_names.resolve}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SOURCE_QUEUE_WORK_ITEMS_NAME=${local.performance_runner_source_queue_names.work_items}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_SOURCE_QUEUE_FINALIZE_NAME=${local.performance_runner_source_queue_names.finalize}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_DLQ_RESOLVE_NAME=${local.performance_runner_dlq_names.resolve}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_DLQ_WORK_ITEMS_NAME=${local.performance_runner_dlq_names.work_items}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERF_DLQ_FINALIZE_NAME=${local.performance_runner_dlq_names.finalize}\" >> \"$environment_file\"",
          "printf \"%s\\n\" \"PERFORMANCE_RESULTS_BUCKET=${aws_s3_bucket.performance_results.id}\" >> \"$environment_file\"",
          "chmod 0644 \"$environment_file\"",

          "printf \"%s\\n\" \"$runner_image\" > /opt/guardbench-performance-runner/image",
          "printf \"%s\\n\" \"$image_digest\" > /opt/guardbench-performance-runner/digest",
          "printf \"%s\\n\" \"$expected_runner_image\" > /opt/guardbench-performance-runner/expected-image",
          "grep \"^INFRA_REVISION=\" \"$environment_file\" | cut -d= -f2- > /opt/guardbench-performance-runner/infra-revision",
          "printf \"%s\\n\" \"$environment_file\" > /opt/guardbench-performance-runner/environment-file",


        ]
      }
    }]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-performance-runner-bootstrap"
    Purpose = "performance-testing"
  }
}
