variable "name" {
  description = "Name prefix for the replica and its supporting resources."
  type        = string
}

variable "source_db_arn" {
  description = "Full ARN of the source database in the primary region. A bare identifier creates a same-region replica instead."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:rds:", var.source_db_arn))
    error_message = "source_db_arn must be a full RDS ARN, not a database identifier."
  }
}

variable "secondary_region_hint" {
  description = "Standby region name. Used only to render the promotion command in outputs."
  type        = string
}

variable "instance_class" {
  description = "Instance class for the replica. Undersizing here means the replica cannot carry production load when promoted."
  type        = string
}

variable "vpc_id" {
  description = "VPC in the standby region."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets in the standby region for the replica subnet group."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires subnets in at least two availability zones."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDRs permitted to reach the replica on the database port."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "replica_multi_az" {
  description = "Run the replica itself as Multi-AZ. Doubles standby cost; worth it when the RTO does not allow for an AZ failure during a regional failover."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention on the replica, so a promoted instance has its own recovery points."
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred backup window in UTC."
  type        = string
  default     = "03:00-04:00"
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on the replica."
  type        = bool
  default     = true
}

variable "enhanced_monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds. 0 disables it."
  type        = number
  default     = 60
}

variable "monitoring_role_arn" {
  description = "IAM role for enhanced monitoring. Required when enhanced_monitoring_interval is non-zero."
  type        = string
  default     = null
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types exported to CloudWatch."
  type        = list(string)
  default     = ["postgresql", "upgrade"]
}

variable "deletion_protection" {
  description = "Block accidental deletion of the replica."
  type        = bool
  default     = true
}

variable "max_replica_lag_seconds" {
  description = "Replica lag that constitutes an RPO breach."
  type        = number
  default     = 300
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified on lag alarms."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
