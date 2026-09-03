# ============================================
# S3 + CloudFront - SPA 정적 프론트엔드 호스팅
# CloudFront 기본 도메인으로 접근 (d1234.cloudfront.net)
# Route 53 / 커스텀 도메인은 나중에 추가 가능
# ============================================

# --- S3 버킷 (프론트엔드 빌드 결과물 저장) ---
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-${var.environment}-frontend"

  tags = {
    Name = "${var.project}-${var.environment}-frontend"
  }
}

# 퍼블릭 액세스 차단 (CloudFront OAC 경유만 허용)
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 버전 관리 활성화 (롤백 지원)
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 정책 - CloudFront OAC에서만 접근 허용
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_cloudfront_distribution.frontend]
}

# --- CloudFront Origin Access Control ---
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project}-${var.environment}-frontend-oac"
  description                       = "OAC for GuardBench frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# SPA 경로만 index.html로 재작성한다.
# default cache behavior에만 연결되어 API 응답 상태와 본문은 변경하지 않는다.
locals {
  # CloudFront stores function source with LF endings even when the repository
  # is checked out with CRLF endings.
  spa_rewrite_function_code = replace(<<-JS
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);

      if (!uri.startsWith('/api/') && !lastSegment.includes('.')) {
        request.uri = '/${var.spa_index_document}';
      }

      return request;
    }
  JS
  , "\r\n", "\n")
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.project}-${var.environment}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless frontend routes to the SPA entry point"
  publish = true
  code    = local.spa_rewrite_function_code
}

# --- CloudFront Distribution ---
resource "aws_cloudfront_distribution" "frontend" {
  # Keep the distribution disabled until the frontend is ready for manual activation.
  enabled             = false
  is_ipv6_enabled     = true
  default_root_object = var.spa_index_document
  comment             = "GuardBench ${var.environment} frontend"
  price_class         = "PriceClass_200" # 아시아 포함, 남미/호주 제외 (비용 절감)

  # 커스텀 도메인 없음 (CloudFront 기본 URL 사용)
  # 나중에 Route 53 + 도메인 추가 시 aliases 블록 추가

  # S3 오리진
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # API 오리진 (프론트에서 /api/* 경로로 백엔드 호출 시 사용)
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "api-backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 기본 동작: S3에서 정적 파일 서빙
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400    # 1일
    max_ttl     = 31536000 # 1년

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  # /api/* 경로는 백엔드 ALB로 프록시 (CORS 우회용)
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "api-backend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
  }

  # CloudFront 기본 인증서 (*.cloudfront.net)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.project}-${var.environment}-frontend-cf"
  }
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}
