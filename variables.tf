variable "name" {
  description = "Workload name. Combined with environment to prefix every resource."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Region serving live traffic."
  type        = string
  default     = "eu-central-1"
}

variable "secondary_region" {
  description = "Standby region. Must differ from primary_region."
  type        = string
  default     = "eu-west-1"
}

# --- DNS -------------------------------------------------------------------

variable "hosted_zone_id" {
  description = "Route53 hosted zone holding the failover record."
  type        = string
}

variable "record_name" {
  description = "FQDN clients resolve, for example app.example.com."
  type        = string
}

variable "primary_alias_name" {
  description = "DNS name of the primary load balancer."
  type        = string
}

variable "primary_alias_zone_id" {
  description = "Hosted zone ID of the primary load balancer."
  type        = string
}

variable "secondary_alias_name" {
  description = "DNS name of the standby load balancer."
  type        = string
}

variable "secondary_alias_zone_id" {
  description = "Hosted zone ID of the standby load balancer."
  type        = string
}

variable "primary_health_check_fqdn" {
  description = "Region-specific hostname probed for the primary. Never the failover record itself."
  type        = string
}

variable "secondary_health_check_fqdn" {
  description = "Region-specific hostname probed for the standby."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Path probed by the health checker. Should exercise the database, not just return 200."
  type        = string
  default     = "/healthz/deep"
}

variable "failure_threshold" {
  description = "Consecutive failed probes before failover."
  type        = number
  default     = 3
}

variable "request_interval" {
  description = "Seconds between health check probes."
  type        = number
  default     = 30
}

# --- S3 --------------------------------------------------------------------

variable "source_bucket_id" {
  description = "Existing source bucket name in the primary region."
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the source bucket."
  type        = string
}

variable "source_kms_key_arn" {
  description = "KMS key encrypting the source bucket."
  type        = string
}

variable "destination_bucket_name" {
  description = "Replica bucket name to create in the standby region."
  type        = string
}

variable "enable_replication_time_control" {
  description = "Enable the 15 minute replication SLA and its lag metrics."
  type        = bool
  default     = true
}

# --- RDS -------------------------------------------------------------------

variable "source_db_arn" {
  description = "Full ARN of the source database in the primary region."
  type        = string
}

variable "replica_instance_class" {
  description = "Instance class for the cross-region replica."
  type        = string
  default     = "db.r6g.large"
}

variable "secondary_vpc_id" {
  description = "VPC in the standby region."
  type        = string
}

variable "secondary_subnet_ids" {
  description = "Subnets in the standby region for the replica."
  type        = list(string)
}

variable "replica_allowed_cidr_blocks" {
  description = "CIDRs permitted to reach the replica."
  type        = list(string)
  default     = []
}

variable "database_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "replica_multi_az" {
  description = "Run the standby replica as Multi-AZ."
  type        = bool
  default     = false
}

variable "max_replica_lag_seconds" {
  description = "Replica lag constituting an RPO breach."
  type        = number
  default     = 300
}

# --- Backup ----------------------------------------------------------------

variable "backup_rules" {
  description = "AWS Backup rules. Every rule copies to the standby region."

  type = map(object({
    schedule                     = string
    start_window_minutes         = optional(number, 60)
    completion_window_minutes    = optional(number, 360)
    enable_continuous_backup     = optional(bool, false)
    cold_storage_after_days      = optional(number)
    delete_after_days            = number
    copy_cold_storage_after_days = optional(number)
    copy_delete_after_days       = number
  }))

  default = {
    daily = {
      schedule                 = "cron(0 2 * * ? *)"
      enable_continuous_backup = true
      delete_after_days        = 35
      copy_delete_after_days   = 35
    }

    monthly = {
      schedule                     = "cron(0 3 1 * ? *)"
      cold_storage_after_days      = 30
      delete_after_days            = 365
      copy_cold_storage_after_days = 30
      copy_delete_after_days       = 365
    }
  }
}

variable "backup_selection_tag_key" {
  description = "Tag key marking a resource for backup."
  type        = string
  default     = "Backup"
}

variable "backup_selection_tag_value" {
  description = "Tag value marking a resource for backup."
  type        = string
  default     = "true"
}

variable "enable_backup_vault_lock" {
  description = "Apply a compliance-mode vault lock to the DR vault. Irreversible."
  type        = bool
  default     = false
}

variable "backup_notification_sns_topic_arn" {
  description = "SNS topic notified on backup, copy or restore failures."
  type        = string
  default     = null
}

# --- Shared ----------------------------------------------------------------

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified by the DR alarms."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
