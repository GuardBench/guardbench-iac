locals {
  queue_names = toset([
    "gb-run-resolve",
    "gb-workitems",
    "gb-run-finalize",
  ])
}

resource "aws_sqs_queue" "dead_letter" {
  for_each = local.queue_names

  name                      = "${var.project}-${var.environment}-${each.value}-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.project}-${var.environment}-${each.value}-dlq"
  }
}

resource "aws_sqs_queue" "source" {
  for_each = local.queue_names

  name                       = "${var.project}-${var.environment}-${each.value}"
  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[each.key].arn
    maxReceiveCount     = 5
  })

  tags = {
    Name = "${var.project}-${var.environment}-${each.value}"
  }
}
