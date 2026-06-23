terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state in S3 - create this bucket manually first
  # See docs/phase1-setup.md for the exact commands
  backend "s3" {
    bucket         = "drupal-aws-tfstate-093796422475"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "drupal-aws-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "drupal-aws"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = "portfolio-project-destroy-after-use"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ============================================================
# VPC - 2 AZs, 3-tier subnets, 2 NAT Gateways
# ============================================================
module "vpc" {
  source = "../../modules/vpc"

  project          = var.project
  environment      = var.environment
  vpc_cidr         = var.vpc_cidr
  azs              = var.availability_zones
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs
}

# ============================================================
# Security Groups
# ============================================================
module "security_groups" {
  source = "../../modules/security-groups"

  project       = var.project
  environment   = var.environment
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr
  admin_ip_cidr = var.admin_ip_cidr
}

# ============================================================
# S3 for Drupal files
# ============================================================
module "s3" {
  source = "../../modules/s3"

  project     = var.project
  environment = var.environment
  suffix      = random_id.suffix.hex
}

# ============================================================
# ALB
# ============================================================
module "alb" {
  source = "../../modules/alb"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  alb_security_group = module.security_groups.alb_sg_id
  certificate_arn    = var.acm_certificate_arn
}

# ============================================================
# RDS - primary + read replica across 2 AZs
# ============================================================
module "rds" {
  source = "../../modules/rds"

  project                   = var.project
  environment               = var.environment
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  db_instance_class         = var.db_instance_class
  database_subnet_ids       = module.vpc.database_subnet_ids
  db_security_group         = module.security_groups.db_sg_id
  suffix                    = random_id.suffix.hex
  replica_availability_zone = var.availability_zones[1]
}

# ============================================================
# ASG - Drupal app servers, capped min2/max4
# ============================================================
module "asg" {
  source = "../../modules/asg"

  project              = var.project
  environment          = var.environment
  ami_id               = var.ec2_ami_id
  instance_type        = var.ec2_instance_type
  private_subnet_ids   = module.vpc.private_subnet_ids
  app_security_group   = module.security_groups.app_sg_id
  alb_target_group_arn = module.alb.target_group_arn
  key_name             = var.ec2_key_name
  db_host              = module.rds.primary_address
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  s3_bucket_name       = module.s3.bucket_name
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  desired_capacity     = var.asg_desired_capacity
}

# ============================================================
# Billing Alarm - safety net
# ============================================================
module "billing_alarm" {
  source = "../../modules/billing-alarm"

  project          = var.project
  environment      = var.environment
  alert_email      = var.billing_alert_email
  budget_limit_usd = var.budget_limit_usd
}
