# ============================================================
# Security Groups Module
# Layered access: Internet -> ALB -> App (ASG) -> RDS
# Nothing skips a layer.
# ============================================================

# ============================================================
# ALB Security Group - the only thing internet can reach
# ============================================================
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Allows HTTP/HTTPS from internet, forwards to app servers"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to app servers in VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project}-${var.environment}-alb-sg"
  }
}

# ============================================================
# App Server Security Group - only ALB and your IP can reach it
# ============================================================
resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "Drupal app servers - only reachable via ALB and admin IP"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH from your admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr]
  }

  ingress {
    description = "Prometheus node exporter from your admin IP only"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr]
  }

  ingress {
    description = "rsync between app servers within the security group itself"
    from_port   = 873
    to_port     = 873
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "SSH between app servers for rsync over SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound - package installs, AWS API, DB connection"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-sg"
  }
}

# ============================================================
# Database Security Group - only app servers can reach RDS
# ============================================================
resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "RDS MySQL - only reachable from app servers"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from app servers only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Response traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project}-${var.environment}-db-sg"
  }
}
