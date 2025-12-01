data "aws_iot_endpoint" "ats" {
  endpoint_type = "iot:Data-ATS"
}

output "iot_endpoint" {
  description = "IoT Core endpoint for device connections"
  value       = data.aws_iot_endpoint.ats.endpoint_address
}

output "thing_type_arn" {
  description = "ARN of the IoT thing type"
  value       = aws_iot_thing_type.device.arn
}

output "policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.device.arn
}

output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

