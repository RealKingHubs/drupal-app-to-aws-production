# ============================================================
# Outputs - used by Ansible (Phase 2) and for verification
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB public DNS - this is your site URL"
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.asg.autoscaling_group_name
}

output "rds_primary_endpoint" {
  description = "RDS primary endpoint - writes go here"
  value       = module.rds.primary_endpoint
  sensitive   = true
}

output "rds_replica_endpoint" {
  description = "RDS read replica endpoint - reads can go here"
  value       = module.rds.replica_endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket for Drupal files"
  value       = module.s3.bucket_name
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "estimated_monthly_cost_note" {
  description = "Reminder - destroy resources when done to stop billing"
  value       = "Run 'terraform destroy' when finished documenting. ALB + 2 NAT GW + replica RDS are the billed items."
}

output "target_group_arn" {
  description = "ALB target group ARN - used to check instance health"
  value       = module.alb.target_group_arn
}