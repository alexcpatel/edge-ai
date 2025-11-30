resource "aws_cloudwatch_event_rule" "hourly_check" {
  name                = "yocto-instance-uptime-check"
  description         = "Check EC2 instance uptime every hour"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.hourly_check.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.instance_alert.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly_check.arn
}

