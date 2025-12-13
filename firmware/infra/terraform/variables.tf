variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "instance_name" {
  description = "Name tag of the EC2 instance to monitor"
  type        = string
  default     = "yocto-builder"
}

variable "alert_threshold_hours" {
  description = "Alert if instance has been running for more than this many hours"
  type        = number
  default     = 5
}

variable "alert_interval_hours" {
  description = "Send alert every N hours after threshold is reached"
  type        = number
  default     = 1
}

variable "archive_after_hours" {
  description = "Auto-archive data volume after instance stopped for this many hours"
  type        = number
  default     = 24
}

variable "notification_email" {
  description = "Email address to receive alerts"
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "yocto-builder-ec2-monitor"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (default: every hour)"
  type        = string
  default     = "rate(1 hour)"
}

# EC2 Instance variables
# Note: AMI is now dynamically fetched using data source (Ubuntu 22.04 LTS)
# variable "instance_ami" is no longer used but kept for backwards compatibility
variable "instance_ami" {
  description = "AMI ID for the EC2 instance (deprecated - now using Ubuntu AMI data source)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type (x86_64)"
  type        = string
  default     = "c7i.2xlarge"
}

variable "instance_key_name" {
  description = "Name of the EC2 key pair"
  type        = string
  default     = "yocto-builder-keypair"
}

variable "instance_subnet_id" {
  description = "Subnet ID for the EC2 instance"
  type        = string
  # No default - must be set in terraform.tfvars (gitignored)
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
  # No default - must be set in terraform.tfvars (gitignored)
}

# Terraform backend configuration
variable "terraform_state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "yocto-builder-terraform-state"
}

variable "terraform_state_lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' (e.g., 'myorg/edge-ai')"
  type        = string
}

variable "artifacts_bucket_name" {
  description = "S3 bucket name for build artifacts"
  type        = string
  default     = "edge-ai-build-artifacts"
}

