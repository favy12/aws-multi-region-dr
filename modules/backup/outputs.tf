output "primary_vault_arn" {
  description = "ARN of the vault in the primary region."
  value       = aws_backup_vault.primary.arn
}

output "secondary_vault_arn" {
  description = "ARN of the DR vault in the standby region."
  value       = aws_backup_vault.secondary.arn
}

output "plan_id" {
  description = "ID of the backup plan."
  value       = aws_backup_plan.this.id
}

output "backup_role_arn" {
  description = "IAM role AWS Backup assumes."
  value       = aws_iam_role.backup.arn
}

output "selection_tag" {
  description = "Tag a resource with this to bring it into the plan."
  value = {
    (var.selection_tag_key) = var.selection_tag_value
  }
}
