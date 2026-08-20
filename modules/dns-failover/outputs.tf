output "primary_health_check_id" {
  description = "ID of the primary health check. Referenced by the failover runbook."
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "ID of the standby health check, or null when monitoring is disabled."
  value       = var.monitor_secondary ? aws_route53_health_check.secondary[0].id : null
}

output "record_fqdn" {
  description = "FQDN clients resolve."
  value       = aws_route53_record.primary.fqdn
}

output "alarm_names" {
  description = "CloudWatch alarms guarding the primary endpoint."
  value       = compact([
    aws_cloudwatch_metric_alarm.primary_unhealthy.alarm_name,
    var.latency_alarm_threshold_ms == null ? "" : aws_cloudwatch_metric_alarm.primary_latency[0].alarm_name,
  ])
}
