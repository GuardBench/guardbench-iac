resource "aws_db_subnet_group" "app" {
  name       = "${var.project}-${var.environment}-db-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project}-${var.environment}-db-subnets"
  }
}

resource "aws_db_instance" "app" {
  identifier = "${var.project}-${var.environment}"

  engine         = "postgres"
  engine_version = "16.14"
  instance_class = "db.t4g.micro"
  db_name        = "guardbench"
  username       = "guardbench"

  manage_master_user_password = true
  storage_encrypted           = true
  storage_type                = "gp3"
  allocated_storage           = 20
  max_allocated_storage       = 100

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = {
    Name = "${var.project}-${var.environment}-postgres"
  }
}
