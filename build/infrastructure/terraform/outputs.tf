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

