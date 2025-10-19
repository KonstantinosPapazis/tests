output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.s3.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.s3.arn
}

output "replication_role_arn" {
  description = "ARN of the replication IAM role (if replication is enabled)"
  value       = var.enable_replication ? aws_iam_role.replication[0].arn : null
}

