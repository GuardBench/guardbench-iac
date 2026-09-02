variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "guardbench"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_oidc_provider_arn" {
  description = "Existing account-wide GitHub Actions OIDC provider ARN; null creates one"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.github_oidc_provider_arn == null || can(regex(
      "^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$",
      var.github_oidc_provider_arn,
    ))
    error_message = "github_oidc_provider_arn must be the token.actions.githubusercontent.com provider ARN."
  }
}

# ============================================
# VPC / 네트워크 설정
# ============================================
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use (2 AZ)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ECS, RDS, VPC Endpoints)"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.20.0/24"]
}

# ============================================
# 서비스 설정
# ============================================
variable "api_container_port" {
  description = "Port exposed by the API container"
  type        = number
  default     = 8080
}

variable "api_cpu" {
  description = "CPU units for API task (1 vCPU = 1024)"
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "Memory (MiB) for API task"
  type        = number
  default     = 1024
}

variable "app_desired_count" {
  description = "Number of combined application tasks"
  type        = number
  default     = 1
}

variable "app_image_tag" {
  description = "Immutable ECR tag for the verified backend commit"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,64}$", var.app_image_tag))
    error_message = "app_image_tag must be a verified Git commit SHA."
  }
}

variable "alarm_email" {
  description = "Optional email address that confirms the dev operations SNS subscription"
  type        = string
  default     = null
  nullable    = true
}

variable "db_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

variable "ecs_db_target" {
  description = "Database target injected into the shared dev ECS task definition"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "performance"], var.ecs_db_target)
    error_message = "ecs_db_target must be either dev or performance."
  }
}

variable "dev_db_instance_class" {
  description = "Instance class for the development RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "dev_db_allocated_storage" {
  description = "Allocated storage in GiB for the development RDS"
  type        = number
  default     = 20
}

variable "dev_db_max_allocated_storage" {
  description = "Maximum autoscaled storage in GiB for the development RDS"
  type        = number
  default     = 100
}

variable "dev_db_backup_retention_period" {
  description = "Backup retention period in days for the development RDS"
  type        = number
  default     = 1
}

variable "performance_db_instance_class" {
  description = "Instance class for the performance-test RDS; set this from the test sizing decision before apply"
  type        = string
  default     = "db.t4g.micro"
}

variable "performance_db_allocated_storage" {
  description = "Allocated storage in GiB for the performance-test RDS"
  type        = number
  default     = 20
}

variable "performance_db_max_allocated_storage" {
  description = "Maximum autoscaled storage in GiB for the performance-test RDS"
  type        = number
  default     = 100
}

variable "performance_db_backup_retention_period" {
  description = "Backup retention period in days for the performance-test RDS"
  type        = number
  default     = 1
}

variable "spa_index_document" {
  description = "Index document for S3 static hosting"
  type        = string
  default     = "index.html"
}
