# GuardBench dev Terraform runbook

이 디렉터리는 `guardbench-dev` 최초 백엔드 배포를 선언한다. `apply` 전에 AWS 실제 리소스와 remote state를 비교한다. 이미 배포된 VPC, subnet, ALB, CloudFront, S3, VPC Endpoint, Security Group, Target Group은 재생성하지 않는다.

## 준비

1. Terraform 1.10 이상과 `ap-northeast-2` AWS credential을 준비한다.
2. `terraform.tfvars.example`을 복사하여 bootstrap에 사용할 `app_image_tag`에 `clean check bootBuildImage`를 통과한 backend commit SHA를 넣는다. 이 값은 최초 Task Definition 생성을 위한 값이며 일반 Backend 배포용이 아니다.
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

계획에서 기존 네트워크, S3, CloudFront, ALB, Target Group의 삭제 또는 교체가 없음을 사람이 확인한 뒤에만 `terraform apply tfplan`을 실행한다. apply는 ECR·RDS·SQS·Secrets Manager Endpoint·단일 ECS App Service·CloudWatch/SNS를 생성하거나 갱신한다. Terraform apply 자체는 Backend application 재배포를 의미하지 않는다.

Bootstrap 시 ECR image는 Terraform apply 전에 push한다. Task Definition은 `latest`가 아닌 immutable commit SHA tag만 받는다. 이후 Backend application 배포는 `app_image_tag` 변경이 아니라 Backend GitHub Actions로 수행한다. `alarm_email`을 설정하면 SNS email subscription이 생성되며 수신자가 AWS confirmation 메일을 승인해야 한다.

Task Definition infrastructure configuration을 변경한 경우에는 Backend issue #142가 적용된 뒤 다음 순서를 따른다.

```text
terraform apply
→ 새로운 base Task Definition revision 등록
→ Backend GitHub Actions deploy
→ Backend #142 workflow가 family의 latest ACTIVE revision을 base로 image만 교체
→ 새로운 deployment revision 등록
→ ECS Service update
```

## Performance RDS 운영 전제

성능 테스트용 RDS는 dev RDS와 별도로 생성되며, private subnet에 위치하고 shared dev ECS API security group에서만 PostgreSQL 접근을 허용한다. ECS와 SQS/DLQ는 dev 환경과 공유한다. 따라서 성능 측정 중에는 다른 dev workload가 없어야 하며, 실행 전 Performance Runner가 기존 TestRun과 Source Queue/DLQ 상태를 검증해야 한다.

기본값인 `ecs_db_target = "dev"`는 기존 dev RDS를 사용한다. 성능 테스트를 위해서는 `ecs_db_target = "performance"`으로 Terraform apply하여 JDBC endpoint와 Secrets Manager username/password가 모두 Performance RDS를 참조하는 baseline Task Definition을 등록한다. 이후 Backend issue #142가 적용된 Backend GitHub Actions deploy를 실행해 latest ACTIVE revision을 기반으로 ECS Service에 반영한다. Performance RDS의 instance class, storage, backup retention 변수에는 default가 없으므로 적용 전에 승인된 성능 계획 값을 모두 명시해야 한다. shared ECS task execution role에는 Dev와 Performance RDS의 두 master secret만 허용해, 전환 중 기존 revision 재시작 또는 circuit breaker rollback도 안전하게 지원한다. credential은 Terraform output이나 task definition plaintext에 노출하지 않는다.

전용 Performance Runner EC2는 `performance_runner_enabled = false`가 기본값이며 일반적인 `dev` 배포에서는 생성하지 않는다. Backend의 `performance/build-runner-image.sh`로 이미지를 빌드하고 Terraform output의 전용 ECR repository에 Backend commit SHA tag로 push한 뒤, 성능 테스트를 실행할 때만 이 값을 `true`로 설정하고 Terraform apply를 수행한다. Spot runner는 `one-time` 요청이므로 테스트 종료 후 인스턴스를 삭제하거나 중단하면 다음 테스트 전에 다시 apply해야 한다.

```bash
runner_repository="$(terraform output -raw performance_runner_ecr_repository_url)"
runner_revision="$(git -C ../guardbench-backend rev-parse HEAD)"
../guardbench-backend/performance/build-runner-image.sh "$runner_repository"
aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin "${runner_repository%%/*}"
../guardbench-backend/bin/publish-runner-image "$runner_repository:$runner_revision"
```

Runner EC2는 ECS Optimized AL2023 AMI를 사용하므로 private subnet에서 별도 Docker 패키지 다운로드가 필요 없다. Terraform apply 후 SSM Command document를 `RunnerImage=$runner_repository:$runner_revision` 파라미터로 실행하면 ECR pull과 image `verify-runtime` 검증이 수행된다. 실제 Runner 실행에 필요한 `PERF_*` 환경변수와 profile/dataset은 Backend 성능테스트 문서의 실행 절차를 따른다.

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

## 백엔드 GitHub Actions OIDC 배포

`backend_github_actions_role_arn`은 `GuardBench/guardbench-backend`의 `dev` Environment에서만 사용할 수 있다. Trust policy는 immutable organization/repository ID와 `environment:dev` subject, audience `sts.amazonaws.com`으로 제한된다. Environment subject에는 branch가 들어가지 않으므로 GitHub repository의 `dev` Environment에서 Deployment branches and tags를 `dev` 브랜치로 제한한다.

```bash
terraform output -raw backend_github_actions_role_arn
gh variable set AWS_DEPLOY_ROLE_ARN \
  --repo GuardBench/guardbench-backend \
  --env dev \
  --body "ROLE_ARN"

gh variable set AWS_REGION --repo GuardBench/guardbench-backend --env dev --body "ap-northeast-2"
gh variable set ECR_REPOSITORY --repo GuardBench/guardbench-backend --env dev --body "guardbench-dev"
gh variable set ECS_CLUSTER --repo GuardBench/guardbench-backend --env dev --body "guardbench-dev-cluster"
gh variable set ECS_SERVICE --repo GuardBench/guardbench-backend --env dev --body "guardbench-dev-app"
gh variable set ECS_CONTAINER_NAME --repo GuardBench/guardbench-backend --env dev --body "app"
# Backend issue #142 적용 후 workflow에서 사용하는 변수
gh variable set ECS_TASK_DEFINITION_FAMILY --repo GuardBench/guardbench-backend --env dev --body "guardbench-dev-app"
```

Backend issue #142 적용 후 backend workflow는 `permissions: id-token: write`, `environment: dev`, `configure-aws-credentials`의 `role-to-assume`, 그리고 다음 리소스 변수를 사용한다. 현재 workflow가 이 계약을 적용하기 전에는 `ECS_TASK_DEFINITION_FAMILY`를 설정해도 Service의 current revision base 문제가 해결되지 않는다.

- `AWS_REGION`: `ap-northeast-2`
- `ECR_REPOSITORY`: `guardbench-dev`
- `ECS_CLUSTER`: `guardbench-dev-cluster`
- `ECS_SERVICE`: `guardbench-dev-app`
- `ECS_CONTAINER_NAME`: `app`
- `ECS_TASK_DEFINITION_FAMILY`: `guardbench-dev-app`

이 Role은 지정된 ECR repository push, `guardbench-dev-app` task definition family 등록, 해당 ECS service 조회·갱신, ECS execution/app task role에 대한 제한된 `iam:PassRole`만 허용한다. Task definition tags를 workflow에서 전달하지 않으므로 `ecs:TagResource`는 부여하지 않는다.

### ECS task definition 소유권

최초 ECS Service와 baseline task definition은 Terraform이 생성한다. 이후 application task definition revision과 Service의 `task_definition` 변경은 Backend GitHub Actions가 소유한다. `aws_ecs_service.app`에는 `task_definition`에 대한 `ignore_changes`가 설정되어 있어 Terraform이 CI가 배포한 revision을 이전 revision으로 되돌리지 않는다. Backend issue #142 적용 후 workflow는 Service의 current revision이 아닌 family의 latest ACTIVE revision을 base로 사용해야 하며, Terraform으로 container definition 자체를 변경한 경우에는 `terraform apply` 후 Backend 배포 workflow를 실행해야 최신 설정이 유지된다. #142 적용 전에는 현재 workflow가 Service current revision을 base로 사용하므로 이 runbook의 latest ACTIVE 보존 계약이 아직 유효하지 않다. 일반 Backend 배포를 위해 `app_image_tag`를 변경하지 않는다.
