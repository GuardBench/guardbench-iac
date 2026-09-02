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

variable "demo_ai_image_tag" {
  description = "Immutable Git SHA tag for the verified Demo AI image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,64}$", var.demo_ai_image_tag))
    error_message = "demo_ai_image_tag must be a verified Git commit SHA; mutable tags such as latest are not allowed."
  }
}

variable "demo_ai_bedrock_model_id" {
  description = "Bedrock model ID passed to the Demo AI container as BEDROCK_MODEL_ID"
  type        = string

  validation {
    condition     = trimspace(var.demo_ai_bedrock_model_id) != ""
    error_message = "demo_ai_bedrock_model_id must be a non-empty approved Bedrock model ID or inference profile ID."
  }
}

variable "demo_ai_bedrock_resource_arns" {
  description = "Exact Bedrock foundation-model and/or inference-profile ARNs allowed for Demo AI InvokeModel"
  type        = list(string)

  validation {
    condition = length(var.demo_ai_bedrock_resource_arns) > 0 && alltrue([
      for resource_arn in var.demo_ai_bedrock_resource_arns : can(regex(
        "^arn:(aws|aws-us-gov|aws-cn):bedrock:[a-z0-9-]+:[0-9]{0,12}:(foundation-model|inference-profile)/.+$",
        resource_arn,
      ))
    ])
    error_message = "demo_ai_bedrock_resource_arns must contain at least one exact Bedrock foundation-model or inference-profile ARN."
  }
}

variable "demo_ai_cpu" {
  description = "CPU units for the Demo AI Fargate task"
  type        = number
  default     = 512
}

variable "demo_ai_memory" {
  description = "Memory (MiB) for the Demo AI Fargate task"
  type        = number
  default     = 1024
}

variable "demo_ai_desired_count" {
  description = "Number of Demo AI Fargate tasks used as the performance-test target"
  type        = number
  default     = 1

  validation {
    condition     = var.demo_ai_desired_count >= 0
    error_message = "demo_ai_desired_count must be zero or greater."
  }
}

variable "demo_ai_enabled" {
  description = "Keep Demo AI tasks running for integrated performance tests"
  type        = bool
  default     = false
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
  description = "Required instance class for the performance-test RDS, set from the approved test sizing decision"
  type        = string
}

variable "performance_db_allocated_storage" {
  description = "Required allocated storage in GiB for the performance-test RDS"
  type        = number
}

variable "performance_db_max_allocated_storage" {
  description = "Required maximum autoscaled storage in GiB for the performance-test RDS"
  type        = number

  validation {
    condition     = var.performance_db_max_allocated_storage >= var.performance_db_allocated_storage
    error_message = "performance_db_max_allocated_storage must be greater than or equal to performance_db_allocated_storage."
  }
}

variable "performance_db_backup_retention_period" {
  description = "Required backup retention period in days for the performance-test RDS"
  type        = number
}

variable "performance_runner_instance_type" {
  description = "EC2 instance type for the dedicated performance-test runner"
  type        = string
  default     = "t3.medium"
}

variable "performance_runner_enabled" {
  description = "Create the dedicated performance-test runner EC2 instance"
  type        = bool
  default     = false
}

variable "performance_runner_root_volume_gb" {
  description = "gp3 root-volume size in GiB for the performance-test runner"
  type        = number
  default     = 20

  validation {
    condition     = var.performance_runner_root_volume_gb >= 8
    error_message = "performance_runner_root_volume_gb must be at least 8 GiB."
  }
}

variable "performance_runner_spot" {
  description = "Launch the performance-test runner as a Spot instance"
  type        = bool
  default     = true
}

variable "spa_index_document" {
  description = "Index document for S3 static hosting"
  type        = string
  default     = "index.html"
}
