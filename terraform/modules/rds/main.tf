# ============================================================
# RDS Module
# Primary db.t2.micro in AZ-a (free tier eligible)
# Read replica db.t2.micro in AZ-b (NOT free tier, ~$4 for 15 days)
# This gives real multi-AZ database resilience without paying
# for full Multi-AZ (~2x cost of a single instance).
# ============================================================

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids  = var.database_subnet_ids
  description = "Database subnets for ${var.project} ${var.environment}"

  tags = {
    Name = "${var.project}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_parameter_group" "mysql" {
  name        = "${var.project}-${var.environment}-mysql-params"
  family      = "mysql8.0"
  description = "MySQL 8.0 parameters tuned for Drupal on free tier"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${var.project}-${var.environment}-mysql-params"
  }
}

# ============================================================
# RDS Primary - db.t2.micro, single-AZ, free tier eligible
# Lives in the database subnet in AZ-a
# ============================================================
resource "aws_db_instance" "primary" {
  identifier = "${var.project}-${var.environment}-mysql-primary-${var.suffix}"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class # db.t2.micro

  allocated_storage = 20 # Free tier covers up to 20GB
  storage_type       = "gp2"
  storage_encrypted  = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  multi_az = false # Single-AZ keeps this inside free tier. Replica below covers AZ redundancy.

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  monitoring_interval = 0 # Enhanced monitoring costs extra, disabled to stay free

  performance_insights_enabled = false # Costs extra on some instance classes, disabled

  publicly_accessible = false

  deletion_protection      = false # False so terraform destroy works cleanly for this demo project
  skip_final_snapshot      = true  # No final snapshot needed since this gets destroyed
  apply_immediately         = true

  tags = {
    Name = "${var.project}-${var.environment}-mysql-primary"
    Role = "primary"
  }
}

# ============================================================
# RDS Read Replica - db.t2.micro in AZ-b
# Replicates from primary automatically. Costs ~$0.017/hr
# since replicas are not free tier eligible, but this is the
# cheapest way to get real cross-AZ database redundancy.
# ============================================================
resource "aws_db_instance" "replica" {
  identifier          = "${var.project}-${var.environment}-mysql-replica-${var.suffix}"
  replicate_source_db = aws_db_instance.primary.identifier

  instance_class = var.db_instance_class

  # Replica must be placed manually in the second AZ
  availability_zone = var.replica_availability_zone

  vpc_security_group_ids = [var.db_security_group]

  storage_encrypted = true
  publicly_accessible = false

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "${var.project}-${var.environment}-mysql-replica"
    Role = "read-replica"
  }
}
