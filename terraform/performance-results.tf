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
