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

## Performance RDS 운영 전제

성능 테스트용 RDS는 dev RDS와 별도로 생성되며, private subnet에 위치하고 shared dev ECS API security group에서만 PostgreSQL 접근을 허용한다. ECS와 SQS/DLQ는 dev 환경과 공유한다. 따라서 성능 측정 중에는 다른 dev workload가 없어야 하며, 실행 전 Performance Runner가 기존 TestRun과 Source Queue/DLQ 상태를 검증해야 한다.

기본값인 `ecs_db_target = "dev"`는 기존 dev RDS를 사용한다. 성능 테스트를 위해서는 `ecs_db_target = "performance"`으로 plan/apply하여 ECS task definition의 JDBC endpoint와 Secrets Manager username/password가 모두 Performance RDS를 참조하게 한다. Performance RDS의 instance class와 storage 변수는 적용 전에 성능 계획에 따라 설정한다. credential은 Terraform output이나 task definition plaintext에 노출하지 않는다.

task definition revision을 외부 배포 workflow가 갱신하는 경우에는 전체 apply 전 `terraform plan`에서 `aws_ecs_service.app`이 현재 정상 revision을 이전 revision으로 바꾸지 않는지 반드시 확인한다.

ECR image는 Terraform apply 전에 push한다. Task Definition은 `latest`가 아닌 immutable commit SHA tag만 받는다. `alarm_email`을 설정하면 SNS email subscription이 생성되며 수신자가 AWS confirmation 메일을 승인해야 한다.

## 프론트엔드 GitHub Actions OIDC 배포

계정에 `token.actions.githubusercontent.com` OIDC provider가 이미 있는지 먼저 확인한다.

```bash
aws iam list-open-id-connect-providers
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

기존 provider가 있으면 `github_oidc_provider_arn`에 ARN을 설정한다. 없으면 Terraform이 provider를 생성한다. 교육용 계정에서 `iam:CreateOpenIDConnectProvider`가 거부될 경우 계정 관리자에게 기존 provider 생성 또는 ARN 제공을 요청하고 이 변수로 재사용한다. frontend deploy role의 trust는 audience `sts.amazonaws.com`과 `GuardBench/guardbench-frontend`의 immutable organization/repository ID가 포함된 custom subject, `refs/heads/main`으로만 제한된다. `workflow_dispatch`도 main ref에서 실행하면 같은 subject 조건을 사용한다.

Role은 dev frontend bucket의 조회 및 object 조회·생성·삭제와 해당 CloudFront distribution의 invalidation만 허용한다. IAM 관리, backend 배포, Terraform 권한은 포함하지 않는다.

apply와 plan 검토 후 frontend repository variable을 등록한다. 이 변경들은 각각 별도 승인을 받은 뒤 실행한다.

```bash
terraform output -raw frontend_github_actions_role_arn
gh variable set AWS_DEPLOY_ROLE_ARN --repo GuardBench/guardbench-frontend --body "ROLE_ARN"
```

frontend workflow는 `permissions: id-token: write`와 `aws-actions/configure-aws-credentials`의 `role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}`를 사용한다. OIDC 배포 성공을 확인하기 전에는 기존 Access Key secrets를 제거하지 않는다.

전환 완료 후 repository의 `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY` secrets를 삭제한다. 롤백이 필요하면 workflow를 직전 revision으로 되돌리고 보관 중인 기존 secrets로 재실행한다. 보안 사고가 원인이면 기존 키를 재사용하지 말고 새 키를 발급한다. Role 자체 롤백은 frontend workflow가 더 이상 사용하지 않음을 확인한 뒤 Terraform에서 제거한다.
