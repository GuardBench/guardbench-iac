# Response Behavior Classifier served by SageMaker LMI/vLLM.
#
# This endpoint is intentionally a first-class Terraform resource rather than
# an externally supplied ARN: its model artifact, serving image, and the exact
# task-role permission must change together.
locals {
  sagemaker_classifier_name          = "guardbench-qwen3-4b"
  sagemaker_classifier_endpoint_name = "guardbench-qwen3-4b-endpoint"
  sagemaker_jumpstart_bucket         = "jumpstart-cache-prod-${var.aws_region}"
}

resource "aws_iam_role" "sagemaker_execution" {
  name        = "guardbench-sagemaker-execution-role"
  description = "GuardBench classifier experiment - Qwen3-4B SageMaker endpoint execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "sagemaker.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sagemaker_execution" {
  name = "guardbench-sagemaker-execution-policy"
  role = aws_iam_role.sagemaker_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadQwenJumpStartArtifacts"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${local.sagemaker_jumpstart_bucket}"
      },
      {
        Sid      = "ReadQwenJumpStartArtifactObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${local.sagemaker_jumpstart_bucket}/*"
      },
      {
        Sid    = "WriteSageMakerEndpointLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
      },
      {
        Sid      = "PullServingContainer"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_sagemaker_model" "classifier" {
  name               = local.sagemaker_classifier_name
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  # SageMaker validates the role while creating the model.  Keep the
  # least-privilege policy in place before that validation begins.
  depends_on = [aws_iam_role_policy.sagemaker_execution]

  primary_container {
    image = "763104351884.dkr.ecr.${var.aws_region}.amazonaws.com/djl-inference:0.36.0-lmi18.0.0-cu128"

    model_data_source {
      s3_data_source {
        s3_data_type     = "S3Prefix"
        s3_uri           = "s3://${local.sagemaker_jumpstart_bucket}/huggingface-reasoning/huggingface-reasoning-qwen3-4b/artifacts/inference-prepack/v2.0.0/"
        compression_type = "None"
      }
    }

    environment = {
      ENDPOINT_SERVER_TIMEOUT        = "3600"
      HF_MODEL_ID                    = "/opt/ml/model"
      MAX_BATCH_SIZE                 = "128"
      MAX_CONCURRENT_REQUESTS        = "256"
      MODEL_CACHE_ROOT               = "/opt/ml/model"
      OPTION_DTYPE                   = "fp16"
      OPTION_ENABLE_CHUNKED_PREFILL  = "true"
      OPTION_GPU_MEMORY_UTILIZATION  = "0.88"
      OPTION_MAX_MODEL_LEN           = "40960"
      OPTION_MAX_NUM_BATCHED_TOKENS  = "81920"
      OPTION_MAX_ROLLING_BATCH_SIZE  = "128"
      OPTION_TENSOR_PARALLEL_DEGREE  = "1"
      OPTION_TOOL_CALL_PARSER        = "hermes"
      SAGEMAKER_ENV                  = "1"
      SAGEMAKER_MODEL_SERVER_TIMEOUT = "3600"
      SAGEMAKER_MODEL_SERVER_WORKERS = "1"
      SAGEMAKER_PROGRAM              = "inference.py"
      SAGEMAKER_SUBMIT_DIRECTORY     = "/opt/ml/model/code"
      TENSOR_PARALLEL_DEGREE         = "1"
      VLLM_ALLOW_LONG_MAX_MODEL_LEN  = "1"
    }
  }
}

resource "aws_sagemaker_endpoint_configuration" "classifier" {
  name = "guardbench-qwen3-4b-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.classifier.name
    initial_instance_count = 1
    initial_variant_weight = 1.0
    instance_type          = "ml.g5.xlarge"
  }
}

resource "aws_sagemaker_endpoint" "classifier" {
  name                 = local.sagemaker_classifier_endpoint_name
  endpoint_config_name = aws_sagemaker_endpoint_configuration.classifier.name
}
