variable "name" {
  description = "Name prefix for the replication role, key alias and alarms."
  type        = string
}

variable "source_bucket_id" {
  description = "Name of the existing source bucket in the primary region. Must already have versioning enabled."
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the source bucket."
  type        = string
}

variable "source_kms_key_arn" {
  description = "KMS key encrypting the source bucket. The replication role needs Decrypt on it."
  type        = string
}

variable "destination_bucket_name" {
  description = "Name of the replica bucket to create in the standby region."
  type        = string
}

variable "replica_storage_class" {
  description = "Storage class for replicated objects. STANDARD_IA is usually right for a replica that is read only during a disaster."
  type        = string
  default     = "STANDARD_IA"

  validation {
    condition     = contains(["STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR"], var.replica_storage_class)
    error_message = "replica_storage_class must be a valid replication-compatible storage class."
  }
}

variable "enable_replication_time_control" {
  description = "Enable S3 RTC: a 15 minute replication SLA plus the CloudWatch metrics needed to alarm on lag. Costs extra per GB."
  type        = bool
  default     = true
}

variable "object_lock_retention_days" {
  description = "Governance-mode object lock on the replica. Null disables it. Requires the bucket to be created with object lock enabled."
  type        = number
  default     = null
}

variable "transition_to_ia_days" {
  description = "Days before replicated objects transition to STANDARD_IA."
  type        = number
  default     = 30
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep noncurrent versions in the replica."
  type        = number
  default     = 90
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified when replication lag breaches the objective."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
