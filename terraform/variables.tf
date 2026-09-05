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

variable "performance_api_cpu" {
  description = "CPU units for the independent Performance Backend task (1 vCPU = 1024)"
  type        = number
  default     = 512

  validation {
    condition     = var.performance_api_cpu > 0 && var.performance_api_cpu == floor(var.performance_api_cpu)
    error_message = "performance_api_cpu must be a positive whole number."
  }
}

variable "performance_api_memory" {
  description = "Memory (MiB) for the independent Performance Backend task"
  type        = number
  default     = 1024

  validation {
    condition     = var.performance_api_memory > 0 && var.performance_api_memory == floor(var.performance_api_memory)
    error_message = "performance_api_memory must be a positive whole number."
  }
}

variable "backend_service_desired_counts" {
  description = "Desired task counts keyed by backend ECS service role; app is the current combined service and api/worker are available for the future split"
  type        = map(number)
  default     = {}

  validation {
    condition = alltrue([
      for desired_count in values(var.backend_service_desired_counts) :
      desired_count >= 0 && desired_count == floor(desired_count)
    ])
    error_message = "backend_service_desired_counts values must be non-negative whole numbers."
  }
}

variable "performance_app_enabled" {
  description = "Create running Performance Backend tasks alongside the development service"
  type        = bool
  default     = false
}

variable "performance_app_desired_count" {
  description = "Number of Performance Backend tasks when the service is enabled"
  type        = number
  default     = 1

  validation {
    condition     = var.performance_app_desired_count >= 0
    error_message = "performance_app_desired_count must be zero or greater."
  }
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
  description = "CPU units for the fixed Demo AI Fargate fixture; keep stable during GuardBench capacity experiments and do not use for MVP capacity sweeps"
  type        = number
  default     = 512
}

variable "demo_ai_memory" {
  description = "Memory (MiB) for the fixed Demo AI Fargate fixture; keep stable during GuardBench capacity experiments and do not use for MVP capacity sweeps"
  type        = number
  default     = 1024
}

variable "demo_ai_desired_count" {
  description = "Number of Demo AI Fargate fixture tasks; keep stable during GuardBench capacity experiments and do not use for MVP capacity sweeps"
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

variable "sagemaker_classifier_system_prompt" {
  description = "Approved fixed system prompt for the SageMaker response behavior classifier; empty leaves the backend classifier safely unconfigured"
  type        = string
  default     = ""
}

variable "sagemaker_classifier_endpoint_enabled" {
  description = "Create the billable ml.g5.xlarge SageMaker real-time endpoint; model, endpoint configuration, IAM, and PrivateLink remain managed when false"
  type        = bool
  default     = false
}

variable "sagemaker_classifier_user_prompt_template" {
  description = "Optional approved user prompt template for the SageMaker classifier; empty uses the backend default"
  type        = string
  default     = ""
}

variable "db_access_host_enabled" {
  description = "Create the private SSM-managed host used for RDS port forwarding"
  type        = bool
  default     = true
}

variable "db_access_host_instance_type" {
  description = "EC2 instance type for the private RDS access host"
  type        = string
  default     = "t3.micro"
}

variable "ecs_db_target" {
  description = "Deprecated compatibility input; backend services no longer use a shared DB target switch"
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
  description = "Instance class for the isolated, fixed Performance RDS dependency used by MVP tests; record the applied value for reproducibility and observe it for bottlenecks. RDS capacity sweep/tuning is outside MVP scope."
  type        = string
}

variable "performance_db_allocated_storage" {
  description = "Configured allocated storage in GiB for the isolated, fixed Performance RDS MVP dependency; record the applied value for reproducibility. RDS capacity sweep/tuning is outside MVP scope."
  type        = number
}

variable "performance_db_max_allocated_storage" {
  description = "Configured maximum allocated storage in GiB for the isolated, fixed Performance RDS MVP dependency; record the applied value for reproducibility. RDS capacity sweep/tuning is outside MVP scope."
  type        = number

  validation {
    condition     = var.performance_db_max_allocated_storage >= var.performance_db_allocated_storage
    error_message = "performance_db_max_allocated_storage must be greater than or equal to performance_db_allocated_storage."
  }
}

variable "performance_db_backup_retention_period" {
  description = "Configured backup retention period in days for the isolated, fixed Performance RDS MVP dependency; record the applied value for reproducibility. RDS capacity sweep/tuning is outside MVP scope."
  type        = number
}

variable "performance_runner_instance_type" {
  description = "EC2 instance type for the dedicated performance-test runner"
  type        = string
  default     = "t3.medium"
}

variable "performance_runner_image_tag" {
  description = "Immutable commit SHA tag for the dedicated Performance Runner image; independent from the Backend application revision"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = !var.performance_runner_enabled || (
      var.performance_runner_image_tag != null
      && can(regex("^[0-9a-f]{40}$", var.performance_runner_image_tag))
    )
    error_message = "performance_runner_image_tag must be the 40-character lowercase Runner image commit SHA when the runner is enabled."
  }
}

variable "performance_runner_infra_revision" {
  description = "Immutable IaC commit SHA recorded for the Performance Runner execution; required when the runner is enabled"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = !var.performance_runner_enabled || (
      var.performance_runner_infra_revision != null
      && can(regex("^[0-9a-f]{40}$", var.performance_runner_infra_revision))
    )
    error_message = "performance_runner_infra_revision must be the 40-character lowercase IaC commit SHA when the runner is enabled."
  }
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
