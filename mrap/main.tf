# ============================================================================
# Multi-Region Access Point (MRAP) Terraform Configuration
# For eu-west-2 (primary) and us-east-2 (replica) buckets
# ============================================================================
#
# Use Case:
# - Developers upload to eu-west-2 only
# - Replication to us-east-2 automatically
# - Generate ONE presigned URL using MRAP
# - European users automatically routed to eu-west-2
# - US users automatically routed to us-east-2
#
# ⚠️ IMPORTANT NOTES:
# - MRAP creation can take up to 24 hours to complete
# - All buckets MUST have versioning enabled
# - Developers need to update code to use MRAP ARN for presigned URLs
# - MRAP has additional costs for request routing
#
# ============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  alias  = "eu_west_2"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"
}

# ============================================================================
# Variables
# ============================================================================

variable "mrap_name" {
  description = "Name for the Multi-Region Access Point (must be globally unique in your account)"
  type        = string
  default     = "my-global-access-point"
}

variable "eu_bucket_name" {
  description = "Name of the existing or new EU bucket (eu-west-2)"
  type        = string
  # If you have existing bucket, set this to its name
  # Example: "my-existing-eu-bucket"
}

variable "us_bucket_name" {
  description = "Name of the existing or new US bucket (us-east-2)"
  type        = string
  # If you have existing bucket, set this to its name
  # Example: "my-existing-us-bucket"
}

variable "create_buckets" {
  description = "Set to false if buckets already exist"
  type        = bool
  default     = true
}

variable "enable_replication_time_control" {
  description = "Enable S3 Replication Time Control (RTC) for predictable replication within 15 minutes"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "mrap-global-access"
  }
}

# ============================================================================
# S3 Buckets in Multiple Regions
# ============================================================================

# EU West 2 Bucket (Primary - where developers upload)
resource "aws_s3_bucket" "eu_west_2" {
  count    = var.create_buckets ? 1 : 0
  provider = aws.eu_west_2
  bucket   = var.eu_bucket_name
  
  tags = merge(var.tags, {
    Region = "eu-west-2"
    Role   = "primary"
  })
}

# US East 2 Bucket (Replica - for US users)
resource "aws_s3_bucket" "us_east_2" {
  count    = var.create_buckets ? 1 : 0
  provider = aws.us_east_2
  bucket   = var.us_bucket_name
  
  tags = merge(var.tags, {
    Region = "us-east-2"
    Role   = "replica"
  })
}

# Use data sources if buckets already exist
data "aws_s3_bucket" "eu_west_2_existing" {
  count    = var.create_buckets ? 0 : 1
  provider = aws.eu_west_2
  bucket   = var.eu_bucket_name
}

data "aws_s3_bucket" "us_east_2_existing" {
  count    = var.create_buckets ? 0 : 1
  provider = aws.us_east_2
  bucket   = var.us_bucket_name
}

# ============================================================================
# Local values for bucket references
# ============================================================================

locals {
  eu_bucket_id  = var.create_buckets ? aws_s3_bucket.eu_west_2[0].id : data.aws_s3_bucket.eu_west_2_existing[0].id
  eu_bucket_arn = var.create_buckets ? aws_s3_bucket.eu_west_2[0].arn : data.aws_s3_bucket.eu_west_2_existing[0].arn
  
  us_bucket_id  = var.create_buckets ? aws_s3_bucket.us_east_2[0].id : data.aws_s3_bucket.us_east_2_existing[0].id
  us_bucket_arn = var.create_buckets ? aws_s3_bucket.us_east_2[0].arn : data.aws_s3_bucket.us_east_2_existing[0].arn
}

# ============================================================================
# Enable Versioning (REQUIRED for MRAP)
# ============================================================================

resource "aws_s3_bucket_versioning" "eu_west_2" {
  provider = aws.eu_west_2
  bucket   = local.eu_bucket_id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "us_east_2" {
  provider = aws.us_east_2
  bucket   = local.us_bucket_id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================================
# S3 Bucket Public Access Block (Best Practice)
# ============================================================================

resource "aws_s3_bucket_public_access_block" "eu_west_2" {
  provider = aws.eu_west_2
  bucket   = local.eu_bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "us_east_2" {
  provider = aws.us_east_2
  bucket   = local.us_bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# IAM Role for Replication
# ============================================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "replication" {
  name = "${var.eu_bucket_name}-replication-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  name = "${var.eu_bucket_name}-replication-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          local.eu_bucket_arn,
          local.us_bucket_arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${local.eu_bucket_arn}/*",
          "${local.us_bucket_arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          "${local.eu_bucket_arn}/*",
          "${local.us_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ============================================================================
# Multi-Region Access Point
# ============================================================================

resource "aws_s3control_multi_region_access_point" "main" {
  details {
    name = var.mrap_name
    
    region {
      bucket = local.eu_bucket_id
    }
    
    region {
      bucket = local.us_bucket_id
    }
    
    public_access_block {
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }
  }
  
  # Ensure versioning is enabled before creating MRAP
  depends_on = [
    aws_s3_bucket_versioning.eu_west_2,
    aws_s3_bucket_versioning.us_east_2
  ]
}

# ============================================================================
# Replication Configuration (EU → US)
# Developers upload to EU, automatically replicates to US
# ============================================================================

resource "aws_s3_bucket_replication_configuration" "eu_to_us" {
  provider = aws.eu_west_2
  
  bucket = local.eu_bucket_id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-eu-to-us"
    status = "Enabled"
    
    # Replicate all objects
    filter {}
    
    destination {
      bucket        = local.us_bucket_arn
      storage_class = "STANDARD"
      
      # Enable Replication Time Control (optional but recommended)
      # Guarantees replication within 15 minutes
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
    
    # Replicate delete markers (optional)
    delete_marker_replication {
      status = "Enabled"
    }
  }
  
  depends_on = [
    aws_s3_bucket_versioning.eu_west_2,
    aws_s3_bucket_versioning.us_east_2
  ]
}

# ============================================================================
# Optional: Bidirectional Replication (US → EU)
# Enable this if you want changes in US bucket to replicate back to EU
# ============================================================================

resource "aws_s3_bucket_replication_configuration" "us_to_eu" {
  provider = aws.us_east_2
  
  # Uncomment to enable bidirectional replication
  # count = 1
  count = 0  # Disabled by default (only EU → US)
  
  bucket = local.us_bucket_id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-us-to-eu"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = local.eu_bucket_arn
      storage_class = "STANDARD"
      
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
    
    delete_marker_replication {
      status = "Enabled"
    }
  }
  
  depends_on = [
    aws_s3_bucket_versioning.us_east_2,
    aws_s3_bucket_versioning.eu_west_2
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "mrap_alias" {
  description = "MRAP alias - use this to construct the MRAP ARN for boto3 presigned URLs"
  value       = aws_s3control_multi_region_access_point.main.alias
}

output "mrap_arn" {
  description = "Full MRAP ARN"
  value       = aws_s3control_multi_region_access_point.main.arn
}

output "mrap_status" {
  description = "MRAP status (can take up to 24 hours to become READY)"
  value       = aws_s3control_multi_region_access_point.main.status
}

output "bucket_names" {
  description = "Names of S3 buckets"
  value = {
    eu_west_2 = local.eu_bucket_id
    us_east_2 = local.us_bucket_id
  }
}

output "account_id" {
  description = "AWS Account ID (needed for boto3 MRAP operations)"
  value       = data.aws_caller_identity.current.account_id
}

output "boto3_mrap_arn" {
  description = "Complete MRAP ARN to use in boto3 code"
  value       = "arn:aws:s3::${data.aws_caller_identity.current.account_id}:accesspoint/${aws_s3control_multi_region_access_point.main.alias}"
}

output "developer_instructions" {
  description = "Instructions for developers"
  value = <<-EOT
    ================================
    MRAP Configuration Complete!
    ================================
    
    1. MRAP ARN: arn:aws:s3::${data.aws_caller_identity.current.account_id}:accesspoint/${aws_s3control_multi_region_access_point.main.alias}
    2. MRAP Alias: ${aws_s3control_multi_region_access_point.main.alias}
    3. Account ID: ${data.aws_caller_identity.current.account_id}
    
    FOR DEVELOPERS:
    ---------------
    
    OLD WAY (bucket-specific presigned URLs):
      url = s3_client.generate_presigned_url('get_object', 
              Params={'Bucket': '${local.eu_bucket_id}', 'Key': 'image.jpg'})
      # Result: Only downloads from EU bucket
    
    NEW WAY (MRAP presigned URLs - automatic routing):
      mrap_arn = "arn:aws:s3::${data.aws_caller_identity.current.account_id}:accesspoint/${aws_s3control_multi_region_access_point.main.alias}"
      url = s3_client.generate_presigned_url('get_object',
              Params={'Bucket': mrap_arn, 'Key': 'image.jpg'})
      # Result: EU users → eu-west-2, US users → us-east-2 (automatic!)
    
    See BOTO3_CLIENT_CONFIGURATION.md for complete code examples.
    
    ⚠️ Note: MRAP may take up to 24 hours to become READY
    Check status: terraform output mrap_status
  EOT
}
