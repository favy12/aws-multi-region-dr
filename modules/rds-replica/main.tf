locals {
  tags = merge(var.tags, {
    "Module" = "rds-replica"
  })
}

resource "aws_db_subnet_group" "replica" {
  provider = aws.secondary

  name       = "${var.name}-replica"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${var.name}-replica"
  })
}

resource "aws_security_group" "replica" {
  provider = aws.secondary

  name        = "${var.name}-replica"
  description = "Cross-region read replica for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-replica"
  })
}

resource "aws_vpc_security_group_ingress_rule" "replica" {
  provider = aws.secondary

  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.replica.id
  description       = "Database access from the standby application tier"
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_kms_key" "replica" {
  provider = aws.secondary

  description             = "Encrypts the ${var.name} cross-region read replica"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_kms_alias" "replica" {
  provider = aws.secondary

  name          = "alias/${var.name}-rds-replica"
  target_key_id = aws_kms_key.replica.key_id
}

# ---------------------------------------------------------------------------
# Cross-region read replica
#
# replicate_source_db takes the full ARN when the source is in another
# region — passing a bare identifier silently creates a same-region replica
# instead, which defeats the entire point.
#
# Replication is asynchronous, so RPO here is however far behind the replica
# is at the moment the primary is lost. That is normally seconds, and is
# measured by the ReplicaLag alarm below.
# ---------------------------------------------------------------------------

resource "aws_db_instance" "replica" {
  provider = aws.secondary

  identifier          = "${var.name}-replica"
  replicate_source_db = var.source_db_arn
  instance_class      = var.instance_class

  db_subnet_group_name   = aws_db_subnet_group.replica.name
  vpc_security_group_ids = [aws_security_group.replica.id]

  kms_key_id        = aws_kms_key.replica.arn
  storage_encrypted = true

  auto_minor_version_upgrade = false
  multi_az                   = var.replica_multi_az

  # Backups on the replica itself, so promoting it does not start life with
  # no recovery point of its own.
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window

  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.enhanced_monitoring_interval
  monitoring_role_arn          = var.enhanced_monitoring_interval == 0 ? null : var.monitoring_role_arn

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-replica-final"
  deletion_protection       = var.deletion_protection

  apply_immediately = false

  tags = merge(local.tags, {
    Name = "${var.name}-replica"
    Role = "dr-replica"
  })

  lifecycle {
    ignore_changes = [
      # Set once at promotion time by the runbook, not by Terraform.
      replicate_source_db,
    ]
  }
}

# ---------------------------------------------------------------------------
# Lag alarm
#
# This is the RPO measurement. If it is breaching, the recovery point in a
# failover is worse than the documented objective and somebody should know
# before the disaster, not during it.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  provider = aws.secondary

  alarm_name        = "${var.name}-replica-lag"
  alarm_description = "Cross-region replica lag exceeds the RPO objective of ${var.max_replica_lag_seconds}s."

  namespace   = "AWS/RDS"
  metric_name = "ReplicaLag"
  statistic   = "Maximum"
  period      = 60

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.max_replica_lag_seconds
  evaluation_periods  = 5

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.identifier
  }

  treat_missing_data = "breaching"

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  tags = local.tags
}
