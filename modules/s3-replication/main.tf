locals {
  tags = merge(var.tags, {
    "Module" = "s3-replication"
  })
}

# ---------------------------------------------------------------------------
# Destination bucket
#
# Created first: replication configuration on the source references it, and
# S3 validates the destination exists at apply time.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "destination" {
  provider = aws.secondary

  bucket = var.destination_bucket_name

  tags = merge(local.tags, {
    Name = var.destination_bucket_name
    Role = "dr-replica"
  })
}

# Versioning is not optional — S3 replication refuses to configure without it
# on both ends, and without it a delete replicates as a delete, which is not
# a backup.
resource "aws_s3_bucket_versioning" "destination" {
  provider = aws.secondary

  bucket = aws_s3_bucket.destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "destination" {
  provider = aws.secondary

  bucket = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "destination" {
  provider = aws.secondary

  description             = "Encrypts the ${var.destination_bucket_name} DR replica"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_kms_alias" "destination" {
  provider = aws.secondary

  name          = "alias/${var.name}-dr-replica"
  target_key_id = aws_kms_key.destination.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  provider = aws.secondary

  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.destination.arn
    }
    bucket_key_enabled = true
  }
}

# Objects replicated into the DR bucket are protected from deletion for the
# retention window even by the account root. This is the control that makes
# the replica useful against ransomware and operator error, not just against
# a region going down.
resource "aws_s3_bucket_object_lock_configuration" "destination" {
  provider = aws.secondary
  count    = var.object_lock_retention_days == null ? 0 : 1

  bucket = aws_s3_bucket.destination.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "destination" {
  provider = aws.secondary

  bucket = aws_s3_bucket.destination.id

  rule {
    id     = "transition-and-expire-noncurrent"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Replication role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "replication_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.primary

  name               = "${var.name}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "replication" {
  statement {
    sid     = "ReadSource"
    effect  = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [var.source_bucket_arn]
  }

  statement {
    sid     = "ReadSourceObjects"
    effect  = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${var.source_bucket_arn}/*"]
  }

  statement {
    sid     = "WriteDestination"
    effect  = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner",
    ]
    resources = ["${aws_s3_bucket.destination.arn}/*"]
  }

  # Replication has to decrypt with the source key and re-encrypt with the
  # destination key. Omitting either side produces objects that appear to
  # replicate and then silently fail.
  statement {
    sid       = "DecryptSource"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.source_kms_key_arn]
  }

  statement {
    sid       = "EncryptDestination"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.destination.arn]
  }
}

resource "aws_iam_policy" "replication" {
  provider = aws.primary

  name   = "${var.name}-s3-replication"
  policy = data.aws_iam_policy_document.replication.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider = aws.primary

  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# ---------------------------------------------------------------------------
# Replication configuration
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_replication_configuration" "this" {
  provider = aws.primary

  bucket = var.source_bucket_id
  role   = aws_iam_role.replication.arn

  rule {
    id       = "dr-replication"
    status   = "Enabled"
    priority = 1

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = var.replica_storage_class

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.destination.arn
      }

      # RTC puts a 15-minute SLA on replication and, more usefully, emits the
      # metrics that let you alarm when objects are falling behind. Without it
      # replication lag is invisible until someone needs the replica.
      dynamic "replication_time" {
        for_each = var.enable_replication_time_control ? [1] : []

        content {
          status = "Enabled"
          time {
            minutes = 15
          }
        }
      }

      dynamic "metrics" {
        for_each = var.enable_replication_time_control ? [1] : []

        content {
          status = "Enabled"
          event_threshold {
            minutes = 15
          }
        }
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.destination,
    aws_iam_role_policy_attachment.replication,
  ]
}

# ---------------------------------------------------------------------------
# Replication lag alarm
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  provider = aws.primary
  count    = var.enable_replication_time_control ? 1 : 0

  alarm_name        = "${var.name}-s3-replication-lag"
  alarm_description = "S3 replication to the DR region is exceeding its 15 minute objective. RPO for object data is degraded."

  namespace   = "AWS/S3"
  metric_name = "ReplicationLatency"
  statistic   = "Maximum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = 900
  evaluation_periods  = 2

  dimensions = {
    SourceBucket      = var.source_bucket_id
    DestinationBucket = aws_s3_bucket.destination.id
    RuleId            = "dr-replication"
  }

  treat_missing_data = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.tags
}
