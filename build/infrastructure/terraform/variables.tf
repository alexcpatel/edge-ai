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

variable "notification_email" {
  description = "Email address to receive alerts"
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "yocto-instance-uptime-alert"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (default: every hour)"
  type        = string
  default     = "rate(1 hour)"
}

# EC2 Instance variables (for importing existing instance)
variable "instance_ami" {
  description = "AMI ID for the EC2 instance (x86_64 Amazon Linux 2023)"
  type        = string
  default     = "ami-0a627a85fdcfabbaa"
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
  default     = "subnet-b8d56ed3"
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
  default     = "vpc-c725b5ac"
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

