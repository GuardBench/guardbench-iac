locals {
  queue_names = toset([
    "gb-run-resolve",
    "gb-workitems",
    "gb-run-finalize",
  ])

  performance_queue_prefix = "${var.project}-${var.environment}-perf"

  # Backend dev defaults: the execution/resolution claim lease is 45s. Keep
  # enough time after the lease window for DB phase work, scheduling delay,
  # and SQS acknowledgement before a message can be delivered again.
  claim_lease_seconds        = 45
  processing_buffer_seconds  = 15
  visibility_timeout_seconds = 90

}

check "sqs_visibility_timeout_contract" {
  assert {
    condition     = local.visibility_timeout_seconds > local.claim_lease_seconds + local.processing_buffer_seconds
    error_message = "SQS visibility timeout must exceed the 45s claim lease and processing buffer."
  }
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
  visibility_timeout_seconds = local.visibility_timeout_seconds
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[each.key].arn
    maxReceiveCount     = 5
  })

  tags = {
    Name = "${var.project}-${var.environment}-${each.value}"
  }
}

resource "aws_sqs_queue" "performance_dead_letter" {
  for_each = local.queue_names

  name                      = "${local.performance_queue_prefix}-${each.value}-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name        = "${local.performance_queue_prefix}-${each.value}-dlq"
    Environment = "performance"
  }
}

resource "aws_sqs_queue" "performance_source" {
  for_each = local.queue_names

  name                       = "${local.performance_queue_prefix}-${each.value}"
  visibility_timeout_seconds = local.visibility_timeout_seconds
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.performance_dead_letter[each.key].arn
    maxReceiveCount     = 5
  })

  tags = {
    Name        = "${local.performance_queue_prefix}-${each.value}"
    Environment = "performance"
  }
}
