variable "project" {
  type        = string
  description = "Project name used as prefix for all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment - used for tagging and resource naming"
}

variable "db_name" {
  type        = string
  description = "Name of the initial database to create in RDS"
}

variable "db_username" {
  type        = string
  description = "Master username for RDS"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Master password for RDS - minimum 16 characters"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class - db.t2.micro for free tier eligibility on primary"
}

variable "database_subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for RDS instances - should be private subnets across multiple AZs for high availability"
}

variable "db_security_group" {
  type        = string
  description = "Security group ID for the RDS instances - should allow MySQL access from app server security group"
}

variable "suffix" {
  type        = string
  description = "Unique suffix for resource names to avoid collisions - use random_id resource in root module"
}

variable "replica_availability_zone" {
  type        = string
  description = "AZ for the read replica - must differ from primary's AZ"
}
