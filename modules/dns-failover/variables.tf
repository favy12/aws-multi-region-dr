variable "name" {
  description = "Name prefix for health checks and alarms."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone holding the failover record."
  type        = string
}

variable "record_name" {
  description = "FQDN of the failover record, for example app.example.com."
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region, used in the record set identifier."
  type        = string
}

variable "secondary_region" {
  description = "Standby AWS region, used in the record set identifier."
  type        = string
}

variable "primary_alias_name" {
  description = "DNS name of the primary load balancer or CloudFront distribution."
  type        = string
}

variable "primary_alias_zone_id" {
  description = "Hosted zone ID of the primary alias target."
  type        = string
}

variable "secondary_alias_name" {
  description = "DNS name of the standby load balancer."
  type        = string
}

variable "secondary_alias_zone_id" {
  description = "Hosted zone ID of the standby alias target."
  type        = string
}

variable "primary_health_check_fqdn" {
  description = "Hostname the health checker probes for the primary. Use a region-specific name, not the failover record itself."
  type        = string
}

variable "secondary_health_check_fqdn" {
  description = "Hostname the health checker probes for the standby."
  type        = string
  default     = null
}

variable "monitor_secondary" {
  description = "Create a health check for the standby. Observability only — it is not attached to the SECONDARY record."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path probed by the health checker. Should exercise the database and critical dependencies, not just return 200."
  type        = string
  default     = "/healthz/deep"
}

variable "failure_threshold" {
  description = "Consecutive failed probes before the endpoint is marked unhealthy."
  type        = number
  default     = 3

  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 10
    error_message = "failure_threshold must be between 1 and 10."
  }
}

variable "request_interval" {
  description = "Seconds between probes. 30 is standard, 10 is fast but costs more per health check."
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.request_interval)
    error_message = "request_interval must be 10 or 30."
  }
}

variable "health_check_regions" {
  description = "Regions the Route53 checkers probe from. Minimum of three is enforced by the API."
  type        = list(string)
  default     = ["us-east-1", "eu-west-1", "ap-southeast-1"]

  validation {
    condition     = length(var.health_check_regions) >= 3
    error_message = "Route53 requires at least three health check regions."
  }
}

variable "latency_alarm_threshold_ms" {
  description = "Connect time in ms that triggers a degradation warning. Null disables the alarm."
  type        = number
  default     = 1000
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified on alarm state changes."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
