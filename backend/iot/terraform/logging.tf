# AWS IoT Core Logging for debugging
# Logs to CloudWatch under "AWSIotLogsV2"

resource "aws_cloudwatch_log_group" "iot_logs" {
  name              = "AWSIotLogsV2"
  retention_in_days = 7
}

resource "aws_iam_role" "iot_logging" {
  name = "edge-ai-iot-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "iot.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "iot_logging" {
  name = "edge-ai-iot-logging-policy"
  role = aws_iam_role.iot_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutMetricFilter",
          "logs:PutRetentionPolicy"
        ]
        Resource = "${aws_cloudwatch_log_group.iot_logs.arn}:*"
      }
    ]
  })
}

resource "aws_iot_logging_options" "main" {
  default_log_level = "DEBUG"
  role_arn          = aws_iam_role.iot_logging.arn

  depends_on = [aws_cloudwatch_log_group.iot_logs]
}

