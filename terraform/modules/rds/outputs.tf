output "primary_endpoint" {
  value       = aws_db_instance.primary.endpoint
  sensitive   = true
  description = "Primary RDS endpoint for connecting app servers to primary for read/write operations"
}
output "primary_address" {
  value       = aws_db_instance.primary.address
  sensitive   = true
  description = "Primary RDS endpoint address for connecting app servers to primary for read/write operations"
}

output "replica_endpoint" {
  value       = aws_db_instance.replica.endpoint
  sensitive   = true
  description = "Read replica endpoint for connecting app servers to read replica for read scaling and failover"
}

output "replica_address" {
  value       = aws_db_instance.replica.address
  sensitive   = true
  description = "Read replica endpoint address for connecting app servers to read replica for read scaling and failover"
}

output "db_port" {
  value       = 3306
  description = "Port number for MySQL connections"
}
