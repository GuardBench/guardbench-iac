# GuardBench dev Terraform runbook

이 디렉터리는 `guardbench-dev` 최초 백엔드 배포를 선언한다. `apply` 전에 AWS 실제 리소스와 remote state를 비교한다. 이미 배포된 VPC, subnet, ALB, CloudFront, S3, VPC Endpoint, Security Group, Target Group은 재생성하지 않는다.

## 준비

1. Terraform 1.10 이상과 `ap-northeast-2` AWS credential을 준비한다.
2. `terraform.tfvars.example`을 복사하여 `app_image_tag`에 `clean check bootBuildImage`를 통과한 backend commit SHA를 넣는다.
3. `terraform init -input=false` 후 `terraform state list`를 실행한다.
4. state에 없는 기존 리소스만 해당 Terraform address로 import한다. import 대상과 ID는 적용 직전에 AWS 조회 결과로 확정한다.

```bash
terraform import aws_vpc.main vpc-...
terraform import 'aws_subnet.public[0]' subnet-...
terraform import aws_lb.main arn:aws:elasticloadbalancing:...
terraform import aws_cloudfront_distribution.frontend DISTRIBUTION_ID
```

## 배포 순서

```bash
terraform fmt -check
terraform validate
terraform plan -out=tfplan
```

계획에서 기존 네트워크, S3, CloudFront, ALB, Target Group의 삭제 또는 교체가 없음을 사람이 확인한 뒤에만 `terraform apply tfplan`을 실행한다. apply는 ECR·RDS·SQS·Secrets Manager Endpoint·단일 ECS App Service·CloudWatch/SNS를 생성하거나 갱신한다.

ECR image는 Terraform apply 전에 push한다. Task Definition은 `latest`가 아닌 immutable commit SHA tag만 받는다. `alarm_email`을 설정하면 SNS email subscription이 생성되며 수신자가 AWS confirmation 메일을 승인해야 한다.
