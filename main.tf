locals {
  name = "${var.name}-${var.environment}"

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "aws-multi-region-dr"
  })
}

# ---------------------------------------------------------------------------
# DNS failover
# ---------------------------------------------------------------------------

module "dns_failover" {
  source = "./modules/dns-failover"

  providers = {
    aws           = aws.primary
    aws.us_east_1 = aws.us_east_1
  }

  name             = local.name
  hosted_zone_id   = var.hosted_zone_id
  record_name      = var.record_name
  primary_region   = var.primary_region
  secondary_region = var.secondary_region

  primary_alias_name    = var.primary_alias_name
  primary_alias_zone_id = var.primary_alias_zone_id

  secondary_alias_name    = var.secondary_alias_name
  secondary_alias_zone_id = var.secondary_alias_zone_id

  primary_health_check_fqdn   = var.primary_health_check_fqdn
  secondary_health_check_fqdn = var.secondary_health_check_fqdn

  health_check_path = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval

  alarm_sns_topic_arns = var.alarm_sns_topic_arns

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Object replication
# ---------------------------------------------------------------------------

module "s3_replication" {
  source = "./modules/s3-replication"

  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  name = local.name

  source_bucket_id   = var.source_bucket_id
  source_bucket_arn  = var.source_bucket_arn
  source_kms_key_arn = var.source_kms_key_arn

  destination_bucket_name = var.destination_bucket_name

  enable_replication_time_control = var.enable_replication_time_control
  alarm_sns_topic_arns            = var.alarm_sns_topic_arns

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Database replication
# ---------------------------------------------------------------------------

module "rds_replica" {
  source = "./modules/rds-replica"

  providers = {
    aws.secondary = aws.secondary
  }

  name                  = local.name
  secondary_region_hint = var.secondary_region

  source_db_arn  = var.source_db_arn
  instance_class = var.replica_instance_class

  vpc_id              = var.secondary_vpc_id
  subnet_ids          = var.secondary_subnet_ids
  allowed_cidr_blocks = var.replica_allowed_cidr_blocks
  port                = var.database_port

  replica_multi_az        = var.replica_multi_az
  max_replica_lag_seconds = var.max_replica_lag_seconds

  alarm_sns_topic_arns = var.alarm_sns_topic_arns

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------

module "backup" {
  source = "./modules/backup"

  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  name  = local.name
  rules = var.backup_rules

  selection_tag_key   = var.backup_selection_tag_key
  selection_tag_value = var.backup_selection_tag_value

  enable_vault_lock          = var.enable_backup_vault_lock
  notification_sns_topic_arn = var.backup_notification_sns_topic_arn

  tags = local.tags
}
