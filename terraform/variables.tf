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

# ============================================
# VPC / 네트워크 설정
# ============================================
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use (2 AZ)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ECS, RDS, VPC Endpoints)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
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

variable "api_desired_count" {
  description = "Number of API tasks"
  type        = number
  default     = 2
}

variable "worker_cpu" {
  description = "CPU units for worker tasks (orchestrator/executor)"
  type        = number
  default     = 512
}

variable "worker_memory" {
  description = "Memory (MiB) for worker tasks"
  type        = number
  default     = 1024
}

variable "worker_desired_count" {
  description = "Number of worker tasks (orchestrator/executor each)"
  type        = number
  default     = 1
}

variable "db_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

variable "spa_index_document" {
  description = "Index document for S3 static hosting"
  type        = string
  default     = "index.html"
}

variable "spa_error_document" {
  description = "Error document for SPA fallback (client-side routing)"
  type        = string
  default     = "index.html"
}
