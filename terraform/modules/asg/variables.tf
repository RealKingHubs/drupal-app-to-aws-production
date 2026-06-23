variable "project" {
  type        = string
  description = "Project name used as prefix for all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "ami_id" {
  type        = string
  description = "ID of the AMI to use for the launch configuration"
}

variable "instance_type" {
  type        = string
  description = "Type of EC2 instance to launch"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the Auto Scaling Group"
}

variable "app_security_group" {
  type        = string
  description = "Security group ID for the application servers"
}

variable "alb_target_group_arn" {
  type        = string
  description = "ARN of the Application Load Balancer target group"
}

variable "key_name" {
  type        = string
  description = "Name of existing EC2 Key Pair for SSH access to app servers"
}

variable "db_host" {
  type        = string
  description = "Host address of the RDS instance"
}

variable "db_name" {
  type        = string
  description = "Name of the database to connect to"
}

variable "db_username" {
  type        = string
  description = "Username for authenticating to the database"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket to use for file storage"
}

variable "min_size" {
  type        = number
  default     = 2
  description = "Minimum instances - matches free tier baseline"
}

variable "max_size" {
  type        = number
  default     = 4
  description = "Hard cap on instances to prevent runaway cost"
}

variable "desired_capacity" {
  type        = number
  default     = 2
  description = "Normal running count - stays within 750 free hours"
}
