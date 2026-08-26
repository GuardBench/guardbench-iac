resource "aws_sns_topic" "ops" {
  name = "${var.project}-${var.environment}-ops"
}

resource "aws_sns_topic_subscription" "ops_email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.ops.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_log_metric_filter" "app_error" {
  name           = "${var.project}-${var.environment}-app-error"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "?ERROR ?Exception"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = "GuardBench/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_error" {
  alarm_name          = "${var.project}-${var.environment}-app-errors"
  alarm_description   = "Application error log entries were detected."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.app_error.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.app_error.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "app_cpu" {
  alarm_name          = "${var.project}-${var.environment}-app-cpu"
  alarm_description   = "Combined ECS app service CPU is above 80 percent."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_oldest_message" {
  for_each = aws_sqs_queue.source

  alarm_name          = "${var.project}-${var.environment}-${each.key}-oldest-message"
  alarm_description   = "The oldest source queue message has been waiting for over one minute."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 60
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    QueueName = each.value.name
  }
}

resource "aws_cloudwatch_metric_alarm" "dead_letter_visible_messages" {
  for_each = aws_sqs_queue.dead_letter

  alarm_name          = "${var.project}-${var.environment}-${each.key}-dlq-messages"
  alarm_description   = "A dead-letter queue contains one or more messages."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    QueueName = each.value.name
  }
}
