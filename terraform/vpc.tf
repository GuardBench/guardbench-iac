# ============================================
# VPC + 서브넷 (2 AZ, 퍼블릭/프라이빗)
# Terraform으로 직접 생성
# ============================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

# ============================================
# Internet Gateway (퍼블릭 서브넷용)
# ============================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# Single NAT Gateway for the dev private subnets. External AI providers are
# not covered by AWS service VPC endpoints, so ECS needs an outbound internet
# path while remaining private and without public task IPs.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${var.project}-${var.environment}-nat-eip"
    Purpose = "private-subnet-egress"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.public[0].id
  connectivity_type = "public"

  tags = {
    Name    = "${var.project}-${var.environment}-nat"
    Purpose = "private-subnet-egress"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================
# 퍼블릭 서브넷 (2 AZ) - ALB 배치
# ============================================
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ============================================
# 프라이빗 서브넷 (2 AZ) - ECS, RDS, VPC Endpoints
# ============================================
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ============================================
# 라우트 테이블 - 퍼블릭
# ============================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================
# 라우트 테이블 - 프라이빗 (외부 경로 없음)
# ============================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-private-rt"
  }
}

# Keep the default route separate from the route table resource so the
# existing manually-created NAT route can be imported without replacing the
# route table or its S3 endpoint route.
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================
# S3 Gateway Endpoint → 프라이빗 라우트 테이블 연결
# ============================================
resource "aws_vpc_endpoint_route_table_association" "s3" {
  route_table_id  = aws_route_table.private.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}
