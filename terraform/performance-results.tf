# Performance run output is kept in a private bucket. Only completed run
# results expire after 30 days; runner images are stored in ECR.
resource "aws_s3_bucket" "performance_results" {
  bucket = "${var.project}-${var.environment}-performance-results-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project}-${var.environment}-performance-results"
    Purpose = "performance-testing"
  }
}

resource "aws_s3_bucket_public_access_block" "performance_results" {
  bucket = aws_s3_bucket.performance_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "performance_results" {
  bucket = aws_s3_bucket.performance_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "performance_results" {
  bucket = aws_s3_bucket.performance_results.id

  rule {
    id     = "expire-performance-results"
    status = "Enabled"

    filter {
      prefix = "performance/results/"
    }

    expiration {
      days = 30
    }
  }
}
# ALB access logs are kept separately from performance results so health-check
# responses can be inspected without mixing operational logs with test output.
resource "aws_s3_bucket" "alb_access_logs" {
  bucket = "${var.project}-${var.environment}-alb-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project}-${var.environment}-alb-access-logs"
    Purpose = "alb-access-logging"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    id     = "expire-public-alb-access-logs"
    status = "Enabled"

    filter {
      prefix = "public/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "expire-performance-alb-access-logs"
    status = "Enabled"

    filter {
      prefix = "performance/"
    }

    expiration {
      days = 7
    }
  }
}

data "aws_iam_policy_document" "alb_access_logs" {
  statement {
    sid    = "AllowElasticLoadBalancingAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_access_logs.arn}/public/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"]
    }
  }

  statement {
    sid    = "AllowElasticLoadBalancingPerformanceAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_access_logs.arn}/performance/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"]
    }
  }

  statement {
    sid    = "AllowElasticLoadBalancingHealthCheckLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.alb_access_logs.arn}/health-public/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
      "${aws_s3_bucket.alb_access_logs.arn}/health-performance/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = data.aws_iam_policy_document.alb_access_logs.json
}
