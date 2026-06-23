# ============================================================
# General
# ============================================================
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "drupal-aws"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Team or person responsible for this infrastructure"
  type        = string
  default     = "kingsley-uchenna"
}

# ============================================================
# Networking
# ============================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Exactly 2 AZs - index 0 is primary, index 1 is secondary"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private app subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for isolated database subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "admin_ip_cidr" {
  description = "Your IP address in CIDR format e.g. 1.2.3.4/32 - used for SSH and metrics access. Find yours at https://checkip.amazonaws.com"
  type        = string
  # No default - must be set in terraform.tfvars
}

# ============================================================
# EC2 / ASG
# ============================================================
variable "ec2_ami_id" {
  description = "AMI ID - Ubuntu 22.04 LTS in us-east-1"
  type        = string
  default     = "ami-0c7217cdde317cfec"
}

variable "ec2_instance_type" {
  description = "Instance type - t2.micro for free tier eligibility"
  type        = string
  default     = "t2.micro"
}

variable "ec2_key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
  # No default - must be set in terraform.tfvars
}

variable "asg_min_size" {
  description = "Minimum ASG instances - matches free tier baseline"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum ASG instances - HARD CAP to control cost"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Normal running instance count"
  type        = number
  default     = 2
}

# ============================================================
# Database
# ============================================================
variable "db_name" {
  description = "Drupal MySQL database name"
  type        = string
  default     = "drupal_db"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "drupal_admin"
}

variable "db_password" {
  description = "Master password for RDS - minimum 16 characters"
  type        = string
  sensitive   = true
  # No default - must be set in terraform.tfvars
}

variable "db_instance_class" {
  description = "RDS instance class - db.t2.micro for free tier eligibility on primary"
  type        = string
  default     = "db.t2.micro"
}

# ============================================================
# Load Balancer / TLS
# ============================================================
variable "acm_certificate_arn" {
  description = "ACM cert ARN for HTTPS - leave empty for HTTP only"
  type        = string
  default     = ""
}

# ============================================================
# Cost Control
# ============================================================
variable "billing_alert_email" {
  description = "Email address to receive billing alarm notifications"
  type        = string
  # No default - must be set in terraform.tfvars
}

variable "budget_limit_usd" {
  description = "Total project budget - alarms fire at 50% and 90%"
  type        = number
  default     = 50
}
