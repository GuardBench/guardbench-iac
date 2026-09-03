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

output "nat_gateway_id" {
  description = "NAT Gateway used by private ECS subnets for external HTTPS egress"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public EIP used by the private-subnet NAT Gateway"
  value       = aws_eip.nat.public_ip
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

output "frontend_github_actions_role_arn" {
  description = "Role ARN used by guardbench-frontend GitHub Actions via OIDC"
  value       = aws_iam_role.frontend_github_actions_deploy.arn
}

output "backend_github_actions_role_arn" {
  description = "Role ARN used by guardbench-backend GitHub Actions via OIDC"
  value       = aws_iam_role.backend_github_actions_deploy.arn
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

output "performance_runner_api_url" {
  description = "Private ALB URL to use as PERF_BASE_URL from the performance runner"
  value       = "http://${aws_lb.performance_api.dns_name}"
}

output "ecs_service_name" {
  description = "Development application ECS service name"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  description = "Development application Terraform-managed baseline task definition ARN"
  value       = aws_ecs_task_definition.app.arn
}

output "performance_ecs_service_name" {
  description = "Dedicated performance application ECS service name"
  value       = aws_ecs_service.performance_app.name
}

output "performance_ecs_task_definition_family" {
  description = "Dedicated performance application ECS task definition family"
  value       = aws_ecs_task_definition.performance_app.family
}

output "ecr_repository_url" {
  description = "ECR repository URL (push images here)"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "Private PostgreSQL endpoint for the development app service"
  value       = aws_db_instance.app.address
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN for the development RDS credentials"
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}

output "performance_rds_endpoint" {
  description = "Private PostgreSQL endpoint for the performance-test RDS"
  value       = aws_db_instance.performance.address
}

output "performance_rds_identifier" {
  description = "Identifier for the performance-test RDS"
  value       = aws_db_instance.performance.identifier
}

output "performance_rds_master_secret_arn" {
  description = "Secrets Manager ARN for the isolated performance RDS credentials"
  value       = aws_db_instance.performance.master_user_secret[0].secret_arn
}

output "db_access_host_instance_id" {
  description = "Private SSM-managed EC2 instance ID for RDS port forwarding"
  value       = var.db_access_host_enabled ? aws_instance.db_access[0].id : null
}

output "db_access_host_private_ip" {
  description = "Private IP of the SSM-managed RDS access host"
  value       = var.db_access_host_enabled ? aws_instance.db_access[0].private_ip : null
}

output "performance_runner_instance_id" {
  description = "SSM-managed EC2 Spot instance used for performance-test runs"
  value       = var.performance_runner_enabled ? aws_instance.performance_runner[0].id : null
}

output "performance_runner_security_group_id" {
  description = "Security group ID for the performance-test runner"
  value       = aws_security_group.performance_runner.id
}

output "performance_runner_bootstrap_document_name" {
  description = "SSM Command document that pulls and verifies the performance runner Docker image"
  value       = aws_ssm_document.performance_runner_bootstrap.name
}

output "performance_runner_ecr_repository_url" {
  description = "Private ECR repository URL for immutable performance runner images"
  value       = aws_ecr_repository.performance_runner.repository_url
}

output "demo_ai_ecr_repository_url" {
  description = "Private ECR repository URL for immutable Demo AI images"
  value       = aws_ecr_repository.demo_ai.repository_url
}

output "demo_ai_ecs_service_name" {
  description = "Dedicated Demo AI ECS service name"
  value       = aws_ecs_service.demo_ai.name
}

output "demo_ai_log_group_name" {
  description = "CloudWatch Log Group for Demo AI task metadata"
  value       = aws_cloudwatch_log_group.demo_ai.name
}

output "performance_target_url" {
  description = "Private internal endpoint for PERF_TARGET_URL"
  value       = "http://${aws_lb.performance_api.dns_name}/v1/chat/completions"
}

output "performance_target_model" {
  description = "OpenAI-compatible model value for PERF_TARGET_MODEL"
  value       = "demo-model"
}

output "performance_target_revision" {
  description = "Immutable Demo AI image tag for performance-test traceability"
  value       = var.demo_ai_image_tag
}

output "performance_results_bucket_name" {
  description = "Private S3 bucket for performance results"
  value       = aws_s3_bucket.performance_results.id
}

output "sqs_queue_urls" {
  description = "Development source queue URLs injected into the app task definition"
  value       = { for name, queue in aws_sqs_queue.source : name => queue.url }
}

output "sqs_queue_names" {
  description = "Development source queue names"
  value       = { for name, queue in aws_sqs_queue.source : name => queue.name }
}

output "sqs_dead_letter_queue_urls" {
  description = "Development dead-letter queue URLs"
  value       = { for name, queue in aws_sqs_queue.dead_letter : name => queue.url }
}

output "sqs_dead_letter_queue_names" {
  description = "Development dead-letter queue names"
  value       = { for name, queue in aws_sqs_queue.dead_letter : name => queue.name }
}

output "performance_sqs_queue_urls" {
  description = "Performance source queue URLs injected into the performance app task definition"
  value       = { for name, queue in aws_sqs_queue.performance_source : name => queue.url }
}

output "performance_sqs_queue_names" {
  description = "Performance source queue names"
  value       = { for name, queue in aws_sqs_queue.performance_source : name => queue.name }
}

output "performance_sqs_dead_letter_queue_urls" {
  description = "Performance dead-letter queue URLs"
  value       = { for name, queue in aws_sqs_queue.performance_dead_letter : name => queue.url }
}

output "performance_sqs_dead_letter_queue_names" {
  description = "Performance dead-letter queue names"
  value       = { for name, queue in aws_sqs_queue.performance_dead_letter : name => queue.name }
}

output "ops_sns_topic_arn" {
  description = "Operations alarm topic; email subscriptions require confirmation"
  value       = aws_sns_topic.ops.arn
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
  description = "Preserved worker security group ID; not attached during the first dev deployment"
  value       = aws_security_group.worker.id
}

output "rds_security_group_id" {
  description = "RDS PostgreSQL security group ID"
  value       = aws_security_group.rds.id
}

output "performance_rds_security_group_id" {
  description = "Security group ID for the performance-test RDS"
  value       = aws_security_group.performance_rds.id
}

output "db_access_security_group_id" {
  description = "Security group ID for the private SSM RDS access host"
  value       = aws_security_group.db_access.id
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

output "alb_access_logs_bucket_name" {
  description = "Private S3 bucket for Public and Performance ALB access logs"
  value       = aws_s3_bucket.alb_access_logs.id
}
