output "destination_bucket_id" {
  description = "Name of the replica bucket."
  value       = aws_s3_bucket.destination.id
}

output "destination_bucket_arn" {
  description = "ARN of the replica bucket."
  value       = aws_s3_bucket.destination.arn
}

output "destination_kms_key_arn" {
  description = "KMS key encrypting the replica."
  value       = aws_kms_key.destination.arn
}

output "replication_role_arn" {
  description = "IAM role S3 assumes to replicate objects."
  value       = aws_iam_role.replication.arn
}
