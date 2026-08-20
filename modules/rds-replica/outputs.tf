output "replica_identifier" {
  description = "Identifier of the replica. Used by the promotion runbook."
  value       = aws_db_instance.replica.identifier
}

output "replica_arn" {
  description = "ARN of the replica."
  value       = aws_db_instance.replica.arn
}

output "replica_endpoint" {
  description = "Connection endpoint for the replica."
  value       = aws_db_instance.replica.endpoint
}

output "replica_security_group_id" {
  description = "Security group attached to the replica."
  value       = aws_security_group.replica.id
}

output "promote_command" {
  description = "Command the failover runbook runs to promote this replica to a standalone primary."
  value       = "aws rds promote-read-replica --db-instance-identifier ${aws_db_instance.replica.identifier} --region ${var.secondary_region_hint}"
}
