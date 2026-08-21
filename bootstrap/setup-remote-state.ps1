# ============================================
# Terraform Remote State 부트스트랩 스크립트
# S3 버킷 생성 (락은 S3 자체 use_lockfile 기능 사용, Terraform >= 1.10)
# 팀에서 한 번만 실행하면 됩니다.
# ============================================

$BUCKET_NAME = "guardbench-terraform-state"
$REGION      = "ap-northeast-2"

Write-Host "=== 1/3: S3 버킷 생성 ===" -ForegroundColor Cyan
aws s3api create-bucket `
  --bucket $BUCKET_NAME `
  --region $REGION `
  --create-bucket-configuration LocationConstraint=$REGION

Write-Host "=== 2/3: S3 버전 관리 활성화 ===" -ForegroundColor Cyan
aws s3api put-bucket-versioning `
  --bucket $BUCKET_NAME `
  --versioning-configuration Status=Enabled

Write-Host "=== 3/3: S3 암호화 설정 ===" -ForegroundColor Cyan
aws s3api put-bucket-encryption `
  --bucket $BUCKET_NAME `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\"}}]}'

Write-Host ""
Write-Host "완료! 이제 terraform init을 실행하세요." -ForegroundColor Green
Write-Host "로컬 state가 있으면 'yes'를 입력해서 remote로 마이그레이션합니다." -ForegroundColor Yellow
