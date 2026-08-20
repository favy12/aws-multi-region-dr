locals {
  tags = merge(var.tags, {
    "Module" = "dns-failover"
  })
}

# ---------------------------------------------------------------------------
# Health checks
#
# Route53 health checkers probe from multiple AWS regions and a record is
# considered unhealthy only once enough of them agree. failure_threshold = 3
# with a 30s request_interval means roughly 90 seconds to detect a hard
# outage, which is the floor for standard health checks.
#
# The health check deliberately targets a deep endpoint rather than "/".
# A "/" that returns 200 while the database is unreachable is exactly the
# failure a DNS failover is supposed to catch and won't.
# ---------------------------------------------------------------------------

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval
  measure_latency   = true

  regions = var.health_check_regions

  tags = merge(local.tags, {
    Name = "${var.name}-primary"
  })
}

resource "aws_route53_health_check" "secondary" {
  count = var.monitor_secondary ? 1 : 0

  fqdn              = var.secondary_health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval
  measure_latency   = true

  regions = var.health_check_regions

  tags = merge(local.tags, {
    Name = "${var.name}-secondary"
  })
}

# ---------------------------------------------------------------------------
# Failover records
#
# SECONDARY has no health check attached by default. If both records are
# health-checked and both fail, Route53 returns the primary anyway ("all
# unhealthy means all healthy"), so attaching one to the secondary buys
# nothing in the total-outage case and can cause a needless NXDOMAIN-like
# outcome in partial ones.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "primary" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier  = "primary-${var.primary_region}"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alias_name
    zone_id                = var.primary_alias_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier = "secondary-${var.secondary_region}"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alias_name
    zone_id                = var.secondary_alias_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# Alarms
#
# Route53 health check metrics only exist in us-east-1 regardless of where
# the endpoint lives, so this alarm has to be created there.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  provider = aws.us_east_1

  alarm_name        = "${var.name}-primary-endpoint-unhealthy"
  alarm_description = "Primary endpoint failing Route53 health checks. DNS failover to ${var.secondary_region} is in progress or has completed."

  namespace   = "AWS/Route53"
  metric_name = "HealthCheckStatus"
  statistic   = "Minimum"
  period      = 60

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 2

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  treat_missing_data = "breaching"

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  tags = local.tags
}

# Latency from the health checkers is the earliest warning that the primary
# is degrading rather than down. A failover triggered at 3am is much less
# unpleasant when something paged at the point it started getting slow.
resource "aws_cloudwatch_metric_alarm" "primary_latency" {
  provider = aws.us_east_1
  count    = var.latency_alarm_threshold_ms == null ? 0 : 1

  alarm_name        = "${var.name}-primary-endpoint-slow"
  alarm_description = "Primary endpoint connect time is elevated. Not yet failing health checks."

  namespace   = "AWS/Route53"
  metric_name = "ConnectionTime"
  statistic   = "Average"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_alarm_threshold_ms
  evaluation_periods  = 3

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  treat_missing_data = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.tags
}
