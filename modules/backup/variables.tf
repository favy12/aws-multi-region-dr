variable "name" {
  description = "Name of the backup plan and primary vault."
  type        = string
}

variable "rules" {
  description = "Backup rules keyed by rule name. Every rule copies to the standby region."

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

  validation {
    condition     = alltrue([for r in var.rules : startswith(r.schedule, "cron(") || startswith(r.schedule, "rate(")])
    error_message = "Each schedule must be a cron() or rate() expression."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.cold_storage_after_days == null || r.delete_after_days >= r.cold_storage_after_days + 90
    ])
    error_message = "AWS Backup requires delete_after to be at least 90 days after cold_storage_after."
  }
}

variable "selection_tag_key" {
  description = "Tag key that marks a resource for backup."
  type        = string
  default     = "Backup"
}

variable "selection_tag_value" {
  description = "Tag value that marks a resource for backup."
  type        = string
  default     = "true"
}

variable "enable_vault_lock" {
  description = "Apply a compliance-mode vault lock to the DR vault. Irreversible once the changeable window elapses."
  type        = bool
  default     = false
}

variable "vault_lock_changeable_for_days" {
  description = "Grace period during which the lock can still be removed. AWS enforces a minimum of 3."
  type        = number
  default     = 3
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention the lock enforces."
  type        = number
  default     = 30
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention the lock permits."
  type        = number
  default     = 365
}

variable "notification_sns_topic_arn" {
  description = "SNS topic notified when a backup, copy or restore job fails. Null disables notifications."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
