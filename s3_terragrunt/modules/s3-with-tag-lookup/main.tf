terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.destination]
    }
  }
}

# KMS Key for S3 bucket encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption - ${var.bucket_name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    var.kms_key_tags,
    {
      Name = "${var.bucket_name}-kms-key"
    }
  )
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.s3.key_id
}

# Data source to lookup destination KMS key by tags (if using tag-based lookup)
data "aws_kms_key" "destination" {
  count    = var.enable_replication && var.use_kms_tag_lookup ? 1 : 0
  provider = aws.destination

  key_id = "alias/${var.replication_destination_kms_alias}"
}

# Alternative: Data source to lookup all KMS keys and filter by tags
data "aws_kms_keys" "destination" {
  count    = var.enable_replication && var.use_kms_tag_lookup && var.replication_destination_kms_alias == "" ? 1 : 0
  provider = aws.destination
}

data "aws_kms_key" "destination_filtered" {
  count    = var.enable_replication && var.use_kms_tag_lookup && var.replication_destination_kms_alias == "" ? length(data.aws_kms_keys.destination[0].keys) : 0
  provider = aws.destination
  key_id   = data.aws_kms_keys.destination[0].keys[count.index]
}

# Local value to determine which KMS ARN to use
locals {
  # Determine destination KMS ARN based on lookup method
  destination_kms_arn = var.enable_replication ? (
    var.use_kms_tag_lookup ? (
      # If using alias lookup
      var.replication_destination_kms_alias != "" ? data.aws_kms_key.destination[0].arn :
      # If filtering by tags, find the matching key
      try(
        [for k in data.aws_kms_key.destination_filtered : k.arn if alltrue([
          for tag_key, tag_value in var.replication_destination_kms_tags :
          lookup(k.tags, tag_key, "") == tag_value
        ])][0],
        ""
      )
    ) : var.replication_destination_kms_arn
  ) : ""
}

# S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = merge(
    var.tags,
    {
      Name = var.bucket_name
    }
  )
}

# S3 Bucket Versioning (required for replication)
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# IAM Role for Replication (only created if replication is enabled)
resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.bucket_name}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Replication
resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.bucket_name}-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.this.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${var.replication_destination_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.s3.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt"
        ]
        # Use the local value that determined the correct KMS ARN
        Resource = local.destination_kms_arn
      }
    ]
  })
}

# S3 Bucket Replication Configuration
resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.this]

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "replicate-all-objects"
    status = "Enabled"

    destination {
      bucket        = var.replication_destination_bucket_arn
      storage_class = var.replication_storage_class

      encryption_configuration {
        # Use the local value that determined the correct KMS ARN
        replica_kms_key_id = local.destination_kms_arn
      }
    }
  }
}

