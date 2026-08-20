locals {
  tags = merge(var.tags, {
    "Module" = "backup"
  })
}

# ---------------------------------------------------------------------------
# Vaults
#
# The destination vault is created first so the copy_action in the plan can
# reference its ARN.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "secondary_vault" {
  provider = aws.secondary

  description             = "Encrypts the ${var.name} DR backup vault"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_backup_vault" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-dr"
  kms_key_arn = aws_kms_key.secondary_vault.arn

  tags = merge(local.tags, {
    Role = "dr-copy-destination"
  })
}

# A vault lock in compliance mode cannot be disabled or shortened by anyone,
# including the account root. That is the point — it is what makes the
# retention claim true rather than aspirational. It is also irreversible, so
# it stays opt-in.
resource "aws_backup_vault_lock_configuration" "secondary" {
  provider = aws.secondary
  count    = var.enable_vault_lock ? 1 : 0

  backup_vault_name   = aws_backup_vault.secondary.name
  changeable_for_days = var.vault_lock_changeable_for_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}

resource "aws_kms_key" "primary_vault" {
  provider = aws.primary

  description             = "Encrypts the ${var.name} primary backup vault"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_backup_vault" "primary" {
  provider = aws.primary

  name        = var.name
  kms_key_arn = aws_kms_key.primary_vault.arn

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Backup role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  provider = aws.primary

  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  provider = aws.primary

  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Plan
#
# Every rule copies to the standby region. A backup that only exists in the
# region that just failed is not a disaster recovery control.
# ---------------------------------------------------------------------------

resource "aws_backup_plan" "this" {
  provider = aws.primary

  name = var.name

  dynamic "rule" {
    for_each = var.rules

    content {
      rule_name         = rule.key
      target_vault_name = aws_backup_vault.primary.name
      schedule          = rule.value.schedule
      start_window      = rule.value.start_window_minutes
      completion_window = rule.value.completion_window_minutes

      # Point-in-time recovery where the resource supports it, so RPO between
      # scheduled snapshots is not a full interval.
      enable_continuous_backup = rule.value.enable_continuous_backup

      lifecycle {
        cold_storage_after = rule.value.cold_storage_after_days
        delete_after       = rule.value.delete_after_days
      }

      copy_action {
        destination_vault_arn = aws_backup_vault.secondary.arn

        lifecycle {
          cold_storage_after = rule.value.copy_cold_storage_after_days
          delete_after       = rule.value.copy_delete_after_days
        }
      }
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Selection
#
# Tag-based rather than an explicit resource list: a new database tagged
# correctly is protected the moment it exists, with no Terraform change and
# no chance of somebody forgetting to add it.
# ---------------------------------------------------------------------------

resource "aws_backup_selection" "this" {
  provider = aws.primary

  name         = "${var.name}-by-tag"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.selection_tag_key
    value = var.selection_tag_value
  }
}

# ---------------------------------------------------------------------------
# Failure notification
#
# A backup plan nobody is watching is a backup plan that has been silently
# failing for four months.
# ---------------------------------------------------------------------------

resource "aws_backup_vault_notifications" "primary" {
  provider = aws.primary
  count    = var.notification_sns_topic_arn == null ? 0 : 1

  backup_vault_name   = aws_backup_vault.primary.name
  sns_topic_arn       = var.notification_sns_topic_arn
  backup_vault_events = ["BACKUP_JOB_FAILED", "COPY_JOB_FAILED", "RESTORE_JOB_FAILED"]
}
