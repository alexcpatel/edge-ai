variable "aws_region" {
  description = "AWS region for IoT resources"
  type        = string
  default     = "us-east-2"
}

variable "thing_type_name" {
  description = "IoT thing type name"
  type        = string
  default     = "edge-ai-device"
}

variable "policy_name" {
  description = "IoT policy name for devices"
  type        = string
  default     = "edge-ai-device-policy"
}

