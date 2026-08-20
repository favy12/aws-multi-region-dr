output "record_fqdn" {
  description = "The failover record clients resolve."
  value       = module.dns_failover.record_fqdn
}

output "primary_health_check_id" {
  description = "Health check governing failover. The runbook references this ID."
  value       = module.dns_failover.primary_health_check_id
}

output "dr_alarm_names" {
  description = "CloudWatch alarms that indicate DR posture is degraded."
  value       = module.dns_failover.alarm_names
}

output "replica_identifier" {
  description = "Cross-region database replica identifier."
  value       = module.rds_replica.replica_identifier
}

output "replica_endpoint" {
  description = "Endpoint of the standby database replica."
  value       = module.rds_replica.replica_endpoint
}

output "promote_replica_command" {
  description = "Promotion command used in step 3 of the failover runbook."
  value       = module.rds_replica.promote_command
}

output "dr_bucket_id" {
  description = "Replica bucket in the standby region."
  value       = module.s3_replication.destination_bucket_id
}

output "dr_backup_vault_arn" {
  description = "Backup vault in the standby region."
  value       = module.backup.secondary_vault_arn
}

output "backup_selection_tag" {
  description = "Tag a resource with this to bring it into the backup plan."
  value       = module.backup.selection_tag
}

output "dr_summary" {
  description = "One-glance view of what protects what, for the game-day checklist."
  value = {
    primary_region   = var.primary_region
    secondary_region = var.secondary_region
    dns_record       = module.dns_failover.record_fqdn
    database_replica = module.rds_replica.replica_identifier
    object_replica   = module.s3_replication.destination_bucket_id
    backup_vault     = module.backup.secondary_vault_arn
  }
}
