data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/ec2_monitor.py"
  output_path = "${path.module}/ec2_monitor.zip"
}

resource "aws_lambda_function" "instance_alert" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "ec2_monitor.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 300 # Increased for snapshot operations

  environment {
    variables = {
      INSTANCE_NAME         = var.instance_name
      ALERT_THRESHOLD_HOURS = var.alert_threshold_hours
      ALERT_INTERVAL_HOURS  = var.alert_interval_hours
      ARCHIVE_AFTER_HOURS   = var.archive_after_hours
      SNS_TOPIC_ARN         = aws_sns_topic.instance_alerts.arn
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

