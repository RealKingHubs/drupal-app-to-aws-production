# ============================================================
# VPC Module
# 2 AZs, 3-tier subnets (public, private, database)
# 2 NAT Gateways - one per AZ for real fault tolerance
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# ============================================================
# Public Subnets - hosts ALB and NAT Gateways
# ============================================================
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

# ============================================================
# Private Subnets - hosts Drupal app servers (ASG)
# No public IP. Reach internet only through NAT Gateway.
# ============================================================
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

# ============================================================
# Database Subnets - isolated, no internet route at all
# ============================================================
resource "aws_subnet" "database" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-database-${var.azs[count.index]}"
    Tier = "database"
  }
}

# ============================================================
# NAT Gateways - one per AZ
# Each private subnet routes through the NAT GW in its own AZ
# This means if one AZ has an issue, the other AZ's outbound
# traffic is unaffected
# ============================================================
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.environment}-nat-eip-${var.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project}-${var.environment}-nat-${var.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================================
# Route Tables
# ============================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ, each pointing to its own NAT GW
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-private-${var.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database subnets - no internet route, fully isolated
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-rt-database"
  }
}

resource "aws_route_table_association" "database" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}
