# ============================================
# VPC Outputs
# ============================================
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# ============================================
# CloudFront / S3 Outputs
# ============================================
output "frontend_url" {
  description = "Frontend URL (CloudFront default domain)"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "s3_frontend_bucket" {
  description = "S3 bucket name for frontend static files"
  value       = aws_s3_bucket.frontend.id
}

output "s3_frontend_bucket_arn" {
  description = "S3 frontend bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

# ============================================
# ALB Outputs
# ============================================
output "api_url" {
  description = "Backend API URL (ALB DNS)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

# ============================================
# ECS / ECR Outputs
# ============================================
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecr_repository_url" {
  description = "ECR repository URL (push images here)"
  value       = aws_ecr_repository.app.repository_url
}

# ============================================
# Security Group Outputs
# ============================================
output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "api_security_group_id" {
  description = "API service security group ID"
  value       = aws_security_group.api.id
}

output "worker_security_group_id" {
  description = "Worker (orchestrator/executor) security group ID"
  value       = aws_security_group.worker.id
}

output "rds_security_group_id" {
  description = "RDS PostgreSQL security group ID"
  value       = aws_security_group.rds.id
}

output "vpc_endpoints_security_group_id" {
  description = "VPC Endpoints security group ID"
  value       = aws_security_group.vpc_endpoints.id
}

# ============================================
# VPC Endpoint Outputs
# ============================================
output "vpc_endpoint_sqs_id" {
  description = "SQS VPC endpoint ID"
  value       = aws_vpc_endpoint.sqs.id
}

output "vpc_endpoint_bedrock_runtime_id" {
  description = "Bedrock Runtime VPC endpoint ID"
  value       = aws_vpc_endpoint.bedrock_runtime.id
}

output "vpc_endpoint_bedrock_id" {
  description = "Bedrock VPC endpoint ID"
  value       = aws_vpc_endpoint.bedrock.id
}

output "vpc_endpoint_ssm_id" {
  description = "SSM VPC endpoint ID"
  value       = aws_vpc_endpoint.ssm.id
}

output "vpc_endpoint_logs_id" {
  description = "CloudWatch Logs VPC endpoint ID"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "ECR API VPC endpoint ID"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_s3_id" {
  description = "S3 Gateway VPC endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}
