output "iot_endpoint" {
  description = "AWS IoT endpoint for devices"
  value       = data.aws_iot_endpoint.ats.endpoint_address
}

output "thing_type_name" {
  description = "IoT thing type name"
  value       = aws_iot_thing_type.device.name
}

output "device_policy_name" {
  description = "IoT policy name for provisioned devices"
  value       = aws_iot_policy.device.name
}

output "fleet_provisioning_template" {
  description = "Fleet provisioning template name"
  value       = aws_iot_provisioning_template.device.name
}

output "claim_cert_arn" {
  description = "ARN of claim certificate for fleet provisioning"
  value       = aws_iot_certificate.claim.arn
}

output "claim_cert_ssm_prefix" {
  description = "SSM parameter prefix for claim certificates"
  value       = "/edge-ai/fleet-provisioning"
}
