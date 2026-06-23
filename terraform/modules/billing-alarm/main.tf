# ============================================================
# Billing Alarm Module
# CloudWatch billing alarms must be created in us-east-1
# regardless of where your resources live.
# Sends an email if estimated charges cross the threshold.
# ============================================================

resource "aws_sns_topic" "billing_alerts" {
  name = "${var.project}-${var.environment}-billing-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Warning alarm at 50% of budget
resource "aws_cloudwatch_metric_alarm" "billing_warning" {
  alarm_name          = "${var.project}-${var.environment}-billing-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600 # 6 hours
  statistic           = "Maximum"
  threshold            = var.budget_limit_usd * 0.5
  alarm_description   = "Estimated AWS charges have crossed 50% of the project budget"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}

# Critical alarm at 90% of budget
resource "aws_cloudwatch_metric_alarm" "billing_critical" {
  alarm_name          = "${var.project}-${var.environment}-billing-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600
  statistic           = "Maximum"
  threshold            = var.budget_limit_usd * 0.9
  alarm_description   = "Estimated AWS charges have crossed 90% of the project budget - consider destroying resources"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}
