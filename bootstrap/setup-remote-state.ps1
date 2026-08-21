# ============================================
# Terraform Remote State 부트스트랩 스크립트
# S3 버킷 + DynamoDB Lock 테이블 생성
# 팀에서 한 번만 실행하면 됩니다.
# ============================================

$BUCKET_NAME = "guardbench-terraform-state"
$TABLE_NAME  = "guardbench-terraform-lock"
$REGION      = "ap-northeast-2"

Write-Host "=== 1/4: S3 버킷 생성 ===" -ForegroundColor Cyan
aws s3api create-bucket `
  --bucket $BUCKET_NAME `
  --region $REGION `
  --create-bucket-configuration LocationConstraint=$REGION

Write-Host "=== 2/4: S3 버전 관리 활성화 ===" -ForegroundColor Cyan
aws s3api put-bucket-versioning `
  --bucket $BUCKET_NAME `
  --versioning-configuration Status=Enabled

Write-Host "=== 3/4: S3 암호화 설정 ===" -ForegroundColor Cyan
aws s3api put-bucket-encryption `
  --bucket $BUCKET_NAME `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\"}}]}'

Write-Host "=== 4/4: DynamoDB Lock 테이블 생성 ===" -ForegroundColor Cyan
aws dynamodb create-table `
  --table-name $TABLE_NAME `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region $REGION

Write-Host ""
Write-Host "완료! 이제 terraform init을 실행하세요." -ForegroundColor Green
Write-Host "로컬 state가 있으면 'yes'를 입력해서 remote로 마이그레이션합니다." -ForegroundColor Yellow
