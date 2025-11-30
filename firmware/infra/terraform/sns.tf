resource "aws_sns_topic" "instance_alerts" {
  name = "yocto-instance-uptime-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.instance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

