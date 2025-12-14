# Device Monitoring: Lifecycle Events + Shadow
# Captures connect/disconnect events and routes to CloudWatch

# CloudWatch Log Group for lifecycle events
resource "aws_cloudwatch_log_group" "lifecycle" {
  name              = "/aws/iot/edge-ai/lifecycle"
  retention_in_days = 14
}

# IAM Role for IoT Rules to write to CloudWatch
resource "aws_iam_role" "iot_cloudwatch" {
  name = "edge-ai-iot-cloudwatch-role"

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

resource "aws_iam_role_policy" "iot_cloudwatch" {
  name = "edge-ai-iot-cloudwatch-policy"
  role = aws_iam_role.iot_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lifecycle.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# IoT Rule: Capture device connect events
resource "aws_iot_topic_rule" "device_connected" {
  name        = "edge_ai_device_connected"
  enabled     = true
  sql         = "SELECT * FROM '$aws/events/presence/connected/+'"
  sql_version = "2016-03-23"

  cloudwatch_logs {
    log_group_name = aws_cloudwatch_log_group.lifecycle.name
    role_arn       = aws_iam_role.iot_cloudwatch.arn
  }

  cloudwatch_metric {
    metric_name      = "DeviceConnected"
    metric_namespace = "EdgeAI/IoT"
    metric_unit      = "Count"
    metric_value     = "1"
    role_arn         = aws_iam_role.iot_cloudwatch.arn
  }
}

# IoT Rule: Capture device disconnect events
resource "aws_iot_topic_rule" "device_disconnected" {
  name        = "edge_ai_device_disconnected"
  enabled     = true
  sql         = "SELECT * FROM '$aws/events/presence/disconnected/+'"
  sql_version = "2016-03-23"

  cloudwatch_logs {
    log_group_name = aws_cloudwatch_log_group.lifecycle.name
    role_arn       = aws_iam_role.iot_cloudwatch.arn
  }

  cloudwatch_metric {
    metric_name      = "DeviceDisconnected"
    metric_namespace = "EdgeAI/IoT"
    metric_unit      = "Count"
    metric_value     = "1"
    role_arn         = aws_iam_role.iot_cloudwatch.arn
  }
}

# IoT Rule: Capture shadow updates for metrics
resource "aws_iot_topic_rule" "shadow_updated" {
  name        = "edge_ai_shadow_updated"
  enabled     = true
  sql         = "SELECT * FROM '$aws/things/+/shadow/update/accepted'"
  sql_version = "2016-03-23"

  cloudwatch_metric {
    metric_name      = "ShadowUpdate"
    metric_namespace = "EdgeAI/IoT"
    metric_unit      = "Count"
    metric_value     = "1"
    role_arn         = aws_iam_role.iot_cloudwatch.arn
  }
}

