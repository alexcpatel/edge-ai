output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.instance_alerts.arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.instance_alert.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.hourly_check.arn
}

output "notification_email" {
  description = "Email address that will receive alerts (check inbox for confirmation)"
  value       = var.notification_email
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (use this in workflow)"
  value       = aws_iam_role.github_actions.arn
}

output "artifacts_bucket_name" {
  description = "S3 bucket name for build artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "yocto_data_volume_id" {
  description = "EBS volume ID for Yocto build data (can be snapshotted)"
  value       = aws_ebs_volume.yocto_data.id
}

