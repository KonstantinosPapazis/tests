# Terraform configuration for mrap creation
_Exported on 10/21/2025 at 21:23:24 GMT+2 from Cursor (1.7.53)_

---

**User**

@mrap/ what is the terraform configuration i need to do in order to create mrap?

---

**Cursor**

I'll help you understand the Terraform configuration needed to create an MRAP (Multi-Region Access Point). Let me first explore the mrap folder to see what's already there.

The `mrap/` folder is currently empty. Let me check the s3_boto folder which seems to have MRAP-related examples:

Based on the code examples in your repository, here's the **Terraform configuration you need to create a Multi-Region Access Point (MRAP)**:

## Core MRAP Terraform Configuration

### 1. **S3 Buckets in Multiple Regions** (with Versioning - Required!)

```hcl
# Buckets in multiple regions
resource "aws_s3_bucket" "us_east" {
  provider = aws.us_east_1
  bucket   = "my-mrap-bucket-us-east-1"
}

resource "aws_s3_bucket" "eu_west" {
  provider = aws.eu_west_1
  bucket   = "my-mrap-bucket-eu-west-1"
}

# Enable versioning (REQUIRED for MRAP)
resource "aws_s3_bucket_versioning" "us_east" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "eu_west" {
  provider = aws.eu_west_1
  bucket   = aws_s3_bucket.eu_west.id
  
  versioning_configuration {
    status = "Enabled"
  }
}
```

### 2. **Multi-Region Access Point Resource**

```hcl
resource "aws_s3control_multi_region_access_point" "main" {
  details {
    name = "my-global-access-point"
    
    region {
      bucket = aws_s3_bucket.us_east.id
    }
    
    region {
      bucket = aws_s3_bucket.eu_west.id
    }
    
    public_access_block {
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }
  }
}
```

### 3. **IAM Role for Replication**

```hcl
resource "aws_iam_role" "replication" {
  name = "s3-mrap-replication-role"
  
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
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  
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
          aws_s3_bucket.us_east.arn,
          aws_s3_bucket.eu_west.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      }
    ]
  })
}
```

### 4. **Bidirectional Replication Configuration**

```hcl
resource "aws_s3_bucket_replication_configuration" "us_to_eu" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  role     = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-to-eu"
    status = "Enabled"
    
    destination {
      bucket        = aws_s3_bucket.eu_west.arn
      storage_class = "STANDARD"
      
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }
}

# Repeat for eu_to_us for bidirectional replication
```

### 5. **Outputs**

```hcl
output "mrap_alias" {
  value       = aws_s3control_multi_region_access_point.main.alias
  description = "Use this alias to construct the MRAP ARN"
}

output "mrap_arn" {
  value = aws_s3control_multi_region_access_point.main.arn
}
```

## Important Notes:

⚠️ **MRAP creation can take up to 24 hours**  
⚠️ **All buckets MUST have versioning enabled**  
⚠️ **Bidirectional replication recommended for active-active setup**  
⚠️ **Use S3 Replication Time Control (S3 RTC) for predictable replication**  
⚠️ **MRAP has additional costs for request routing**

## Provider Configuration

Don't forget to configure multiple AWS providers:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}
```

Would you like me to create a complete working Terraform module in the `mrap/` folder with this configuration?

```plaintext
# Buckets in multiple regions
resource "aws_s3_bucket" "us_east" {
  provider = aws.us_east_1
  bucket   = "my-mrap-bucket-us-east-1"
}

resource "aws_s3_bucket" "eu_west" {
  provider = aws.eu_west_1
  bucket   = "my-mrap-bucket-eu-west-1"
}

# Enable versioning (REQUIRED for MRAP)
resource "aws_s3_bucket_versioning" "us_east" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "eu_west" {
  provider = aws.eu_west_1
  bucket   = aws_s3_bucket.eu_west.id
  
  versioning_configuration {
    status = "Enabled"
  }
}
```

```plaintext
resource "aws_s3control_multi_region_access_point" "main" {
  details {
    name = "my-global-access-point"
    
    region {
      bucket = aws_s3_bucket.us_east.id
    }
    
    region {
      bucket = aws_s3_bucket.eu_west.id
    }
    
    public_access_block {
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }
  }
}
```

```plaintext
resource "aws_iam_role" "replication" {
  name = "s3-mrap-replication-role"
  
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
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  
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
          aws_s3_bucket.us_east.arn,
          aws_s3_bucket.eu_west.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      }
    ]
  })
}
```

```plaintext
resource "aws_s3_bucket_replication_configuration" "us_to_eu" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  role     = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-to-eu"
    status = "Enabled"
    
    destination {
      bucket        = aws_s3_bucket.eu_west.arn
      storage_class = "STANDARD"
      
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }
}

# Repeat for eu_to_us for bidirectional replication
```

```plaintext
output "mrap_alias" {
  value       = aws_s3control_multi_region_access_point.main.alias
  description = "Use this alias to construct the MRAP ARN"
}

output "mrap_arn" {
  value = aws_s3control_multi_region_access_point.main.arn
}
```

```plaintext
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}
```

---

**User**

in the mrap folder create 1 terraform file for mrap configuration and another file on what ii should configure in the boto3 s3 client 

---

**Cursor**

I'll create two files in the `mrap/` folder: one with the complete Terraform configuration for MRAP, and another with boto3 client configuration instructions.

```plaintext
# ============================================================================
# Multi-Region Access Point (MRAP) Terraform Configuration
# ============================================================================
#
# This configuration creates:
# - S3 buckets in multiple regions
# - Versioning enabled on all buckets (required for MRAP)
# - Multi-Region Access Point
# - IAM role for replication
# - Bidirectional replication between buckets
#
# ⚠️ IMPORTANT NOTES:
# - MRAP creation can take up to 24 hours to complete
# - All buckets MUST have versioning enabled
# - Bidirectional replication recommended for active-active setup
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
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

# ============================================================================
# Variables
# ============================================================================

variable "mrap_name" {
  description = "Name for the Multi-Region Access Point (must be globally unique in your account)"
  type        = string
  default     = "my-global-access-point"
}

variable "bucket_prefix" {
  description = "Prefix for bucket names"
  type        = string
  default     = "my-mrap-bucket"
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
    Purpose     = "mrap"
  }
}

# ============================================================================
# S3 Buckets in Multiple Regions
# ============================================================================

resource "aws_s3_bucket" "us_east_1" {
  provider = aws.us_east_1
  bucket   = "${var.bucket_prefix}-us-east-1"
  
  tags = merge(var.tags, {
    Region = "us-east-1"
  })
}

resource "aws_s3_bucket" "eu_west_1" {
  provider = aws.eu_west_1
  bucket   = "${var.bucket_prefix}-eu-west-1"
  
  tags = merge(var.tags, {
    Region = "eu-west-1"
  })
}

resource "aws_s3_bucket" "ap_southeast_1" {
  provider = aws.ap_southeast_1
  bucket   = "${var.bucket_prefix}-ap-southeast-1"
  
  tags = merge(var.tags, {
    Region = "ap-southeast-1"
  })
}

# ============================================================================
# Enable Versioning (REQUIRED for MRAP)
# ============================================================================

resource "aws_s3_bucket_versioning" "us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east_1.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "eu_west_1" {
  provider = aws.eu_west_1
  bucket   = aws_s3_bucket.eu_west_1.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "ap_southeast_1" {
  provider = aws.ap_southeast_1
  bucket   = aws_s3_bucket.ap_southeast_1.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================================
# S3 Bucket Public Access Block (Best Practice)
# ============================================================================

resource "aws_s3_bucket_public_access_block" "us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east_1.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "eu_west_1" {
  provider = aws.eu_west_1
  bucket   = aws_s3_bucket.eu_west_1.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "ap_southeast_1" {
  provider = aws.ap_southeast_1
  bucket   = aws_s3_bucket.ap_southeast_1.id

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
  name = "${var.bucket_prefix}-replication-role"
  
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
  name = "${var.bucket_prefix}-replication-policy"
  
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
          aws_s3_bucket.us_east_1.arn,
          aws_s3_bucket.eu_west_1.arn,
          aws_s3_bucket.ap_southeast_1.arn
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
          "${aws_s3_bucket.us_east_1.arn}/*",
          "${aws_s3_bucket.eu_west_1.arn}/*",
          "${aws_s3_bucket.ap_southeast_1.arn}/*"
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
          "${aws_s3_bucket.us_east_1.arn}/*",
          "${aws_s3_bucket.eu_west_1.arn}/*",
          "${aws_s3_bucket.ap_southeast_1.arn}/*"
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
      bucket = aws_s3_bucket.us_east_1.id
    }
    
    region {
      bucket = aws_s3_bucket.eu_west_1.id
    }
    
    region {
      bucket = aws_s3_bucket.ap_southeast_1.id
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
    aws_s3_bucket_versioning.us_east_1,
    aws_s3_bucket_versioning.eu_west_1,
    aws_s3_bucket_versioning.ap_southeast_1
  ]
}

# ============================================================================
# Bidirectional Replication Configuration
# ============================================================================

# US East 1 → EU West 1
resource "aws_s3_bucket_replication_configuration" "us_east_to_eu_west" {
  provider = aws.us_east_1
  
  bucket = aws_s3_bucket.us_east_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-us-east-to-eu-west"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.eu_west_1.arn
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
    aws_s3_bucket_versioning.us_east_1,
    aws_s3_bucket_versioning.eu_west_1
  ]
}

# US East 1 → AP Southeast 1
resource "aws_s3_bucket_replication_configuration" "us_east_to_ap_southeast" {
  provider = aws.us_east_1
  
  bucket = aws_s3_bucket.us_east_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-us-east-to-ap-southeast"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.ap_southeast_1.arn
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
    aws_s3_bucket_versioning.us_east_1,
    aws_s3_bucket_versioning.ap_southeast_1
  ]
}

# EU West 1 → US East 1
resource "aws_s3_bucket_replication_configuration" "eu_west_to_us_east" {
  provider = aws.eu_west_1
  
  bucket = aws_s3_bucket.eu_west_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-eu-west-to-us-east"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.us_east_1.arn
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
    aws_s3_bucket_versioning.eu_west_1,
    aws_s3_bucket_versioning.us_east_1
  ]
}

# EU West 1 → AP Southeast 1
resource "aws_s3_bucket_replication_configuration" "eu_west_to_ap_southeast" {
  provider = aws.eu_west_1
  
  bucket = aws_s3_bucket.eu_west_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-eu-west-to-ap-southeast"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.ap_southeast_1.arn
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
    aws_s3_bucket_versioning.eu_west_1,
    aws_s3_bucket_versioning.ap_southeast_1
  ]
}

# AP Southeast 1 → US East 1
resource "aws_s3_bucket_replication_configuration" "ap_southeast_to_us_east" {
  provider = aws.ap_southeast_1
  
  bucket = aws_s3_bucket.ap_southeast_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-ap-southeast-to-us-east"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.us_east_1.arn
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
    aws_s3_bucket_versioning.ap_southeast_1,
    aws_s3_bucket_versioning.us_east_1
  ]
}

# AP Southeast 1 → EU West 1
resource "aws_s3_bucket_replication_configuration" "ap_southeast_to_eu_west" {
  provider = aws.ap_southeast_1
  
  bucket = aws_s3_bucket.ap_southeast_1.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-ap-southeast-to-eu-west"
    status = "Enabled"
    
    filter {}
    
    destination {
      bucket        = aws_s3_bucket.eu_west_1.arn
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
    aws_s3_bucket_versioning.ap_southeast_1,
    aws_s3_bucket_versioning.eu_west_1
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "mrap_alias" {
  description = "MRAP alias - use this to construct the MRAP ARN for boto3"
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
  description = "Names of all S3 buckets"
  value = {
    us_east_1      = aws_s3_bucket.us_east_1.id
    eu_west_1      = aws_s3_bucket.eu_west_1.id
    ap_southeast_1 = aws_s3_bucket.ap_southeast_1.id
  }
}

output "account_id" {
  description = "AWS Account ID (needed for boto3 MRAP operations)"
  value       = data.aws_caller_identity.current.account_id
}

output "boto3_mrap_arn_format" {
  description = "Format for constructing MRAP ARN in boto3"
  value       = "arn:aws:s3::${data.aws_caller_identity.current.account_id}:accesspoint/${aws_s3control_multi_region_access_point.main.alias}"
}

```

```markdown
# Boto3 S3 Client Configuration for MRAP

This guide explains how to configure the boto3 S3 client to work with Multi-Region Access Points (MRAP).

## Prerequisites

After running `terraform apply` on the `main.tf` file, you'll have:
- ✅ S3 buckets in multiple regions (us-east-1, eu-west-1, ap-southeast-1)
- ✅ Multi-Region Access Point created (can take up to 24 hours!)
- ✅ Bidirectional replication configured

From Terraform outputs, you'll need:
- `mrap_alias` - The unique alias for your MRAP
- `account_id` - Your AWS Account ID

## Step 1: Create S3 Client with MRAP Configuration

**CRITICAL**: You MUST enable `use_arn_region` for MRAP to work!

```python
import boto3
from botocore.config import Config

def create_s3_client_with_mrap():
    """
    Create boto3 S3 client configured for Multi-Region Access Points.
    
    Important: Must use S3 ARN format and enable use_arn_region.
    """
    s3_client = boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,      # ⚠️ REQUIRED for MRAP!
                'addressing_style': 'virtual'
            }
        )
    )
    return s3_client
```

## Step 2: Construct the MRAP ARN

```python
def get_mrap_arn(account_id, mrap_alias):
    """
    Construct the MRAP ARN from your Terraform outputs.
    
    Args:
        account_id: From terraform output 'account_id'
        mrap_alias: From terraform output 'mrap_alias'
    
    Returns:
        MRAP ARN in format: arn:aws:s3::account-id:accesspoint/mrap-alias
    """
    return f"arn:aws:s3::{account_id}:accesspoint/{mrap_alias}"

# Example:
ACCOUNT_ID = "123456789012"  # From terraform output 'account_id'
MRAP_ALIAS = "xxxxxxxx.mrap"  # From terraform output 'mrap_alias'

mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)
# Result: arn:aws:s3::123456789012:accesspoint/xxxxxxxx.mrap
```

## Step 3: Use MRAP ARN as "Bucket" Parameter

**Key Concept**: When using MRAP, you pass the MRAP ARN where you would normally pass the bucket name.

### Upload File

```python
s3_client = create_s3_client_with_mrap()
mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)

# Use MRAP ARN as the "bucket" parameter
s3_client.upload_file(
    Filename='./local_file.txt',
    Bucket=mrap_arn,  # ⚠️ Use MRAP ARN, not bucket name!
    Key='folder/file.txt'
)
```

### Download File

```python
s3_client.download_file(
    Bucket=mrap_arn,
    Key='folder/file.txt',
    Filename='./downloaded_file.txt'
)
```

### Put Object

```python
s3_client.put_object(
    Bucket=mrap_arn,
    Key='test.json',
    Body=json.dumps({'message': 'Hello from MRAP'}),
    ContentType='application/json'
)
```

### Get Object

```python
response = s3_client.get_object(
    Bucket=mrap_arn,
    Key='test.json'
)
data = response['Body'].read()
```

### List Objects

```python
response = s3_client.list_objects_v2(
    Bucket=mrap_arn,
    Prefix='folder/',
    MaxKeys=100
)

for obj in response.get('Contents', []):
    print(f"Key: {obj['Key']}, Size: {obj['Size']} bytes")
```

## Step 4: Generate Presigned URLs with MRAP

```python
def generate_presigned_url_with_mrap(mrap_arn, object_key, expiration=3600):
    """
    Generate presigned URL using MRAP.
    
    Note: Presigned URLs with MRAP will route to the optimal region automatically.
    """
    s3_client = create_s3_client_with_mrap()
    
    presigned_url = s3_client.generate_presigned_url(
        'get_object',
        Params={
            'Bucket': mrap_arn,  # Use MRAP ARN
            'Key': object_key
        },
        ExpiresIn=expiration
    )
    return presigned_url

# Example
url = generate_presigned_url_with_mrap(mrap_arn, 'folder/file.txt', expiration=3600)
print(f"Presigned URL: {url}")
# Users can access this URL from anywhere, and it will route to the nearest region!
```

## Complete Example

```python
#!/usr/bin/env python3
"""
Complete example of using MRAP with boto3
"""
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from Terraform outputs
ACCOUNT_ID = "123456789012"      # terraform output account_id
MRAP_ALIAS = "xxxxxxxx.mrap"     # terraform output mrap_alias

def create_s3_client_with_mrap():
    """Create S3 client configured for MRAP"""
    return boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,
                'addressing_style': 'virtual'
            }
        )
    )

def get_mrap_arn(account_id, mrap_alias):
    """Construct MRAP ARN"""
    return f"arn:aws:s3::{account_id}:accesspoint/{mrap_alias}"

def main():
    # Initialize
    s3_client = create_s3_client_with_mrap()
    mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)
    
    logger.info(f"Using MRAP ARN: {mrap_arn}")
    
    try:
        # Upload a file
        logger.info("Uploading file via MRAP...")
        s3_client.put_object(
            Bucket=mrap_arn,
            Key='test-file.txt',
            Body=b'Hello from Multi-Region Access Point!'
        )
        logger.info("✓ Upload successful")
        
        # Download the file
        logger.info("Downloading file via MRAP...")
        response = s3_client.get_object(
            Bucket=mrap_arn,
            Key='test-file.txt'
        )
        content = response['Body'].read()
        logger.info(f"✓ Downloaded: {content.decode('utf-8')}")
        
        # List objects
        logger.info("Listing objects via MRAP...")
        response = s3_client.list_objects_v2(
            Bucket=mrap_arn,
            MaxKeys=10
        )
        for obj in response.get('Contents', []):
            logger.info(f"  - {obj['Key']} ({obj['Size']} bytes)")
        
        # Generate presigned URL
        logger.info("Generating presigned URL...")
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': mrap_arn,
                'Key': 'test-file.txt'
            },
            ExpiresIn=3600
        )
        logger.info(f"✓ Presigned URL: {url}")
        
    except ClientError as e:
        logger.error(f"Error: {e}")
        raise

if __name__ == "__main__":
    main()
```

## Checking MRAP Status

Before using MRAP, verify it's ready (can take up to 24 hours after `terraform apply`):

```python
import boto3

def check_mrap_status(account_id, mrap_name):
    """
    Check if MRAP is ready to use.
    
    Args:
        account_id: Your AWS Account ID
        mrap_name: The name you gave to MRAP (e.g., 'my-global-access-point')
    
    Returns:
        dict with status, alias, and region information
    """
    s3control_client = boto3.client('s3control')
    
    response = s3control_client.get_multi_region_access_point(
        AccountId=account_id,
        Name=mrap_name
    )
    
    mrap = response['AccessPoint']
    
    return {
        'name': mrap['Name'],
        'status': mrap['Status'],  # Should be 'READY'
        'alias': mrap.get('Alias', 'N/A'),
        'created_at': mrap.get('CreatedAt', 'N/A'),
        'regions': mrap.get('Regions', [])
    }

# Check status
status = check_mrap_status(ACCOUNT_ID, "my-global-access-point")
print(f"MRAP Status: {status['status']}")
print(f"MRAP Alias: {status['alias']}")

if status['status'] != 'READY':
    print("⚠️ MRAP is not ready yet. Please wait (can take up to 24 hours).")
else:
    print("✓ MRAP is ready to use!")
```

## List All MRAPs

```python
def list_all_mraps(account_id):
    """List all Multi-Region Access Points in your account"""
    s3control_client = boto3.client('s3control')
    
    response = s3control_client.list_multi_region_access_points(
        AccountId=account_id
    )
    
    mraps = response.get('AccessPoints', [])
    
    for mrap in mraps:
        print(f"Name: {mrap['Name']}")
        print(f"Status: {mrap['Status']}")
        print(f"Alias: {mrap.get('Alias', 'N/A')}")
        print(f"Regions: {len(mrap.get('Regions', []))}")
        print("---")
    
    return mraps

list_all_mraps(ACCOUNT_ID)
```

## Common Configuration Errors

### ❌ ERROR 1: Not using `use_arn_region`

```python
# BAD - Will not work with MRAP!
s3_client = boto3.client('s3')
s3_client.upload_file('file.txt', mrap_arn, 'file.txt')
# Error: InvalidRequest: The ARN is not supported for this operation
```

**Fix**: Always enable `use_arn_region`:
```python
# GOOD
s3_client = boto3.client(
    's3',
    config=Config(s3={'use_arn_region': True})
)
```

### ❌ ERROR 2: Using bucket name instead of MRAP ARN

```python
# BAD - Using bucket name
s3_client.upload_file('file.txt', 'my-mrap-bucket-us-east-1', 'file.txt')
# This uploads to specific bucket, not via MRAP!
```

**Fix**: Always use MRAP ARN:
```python
# GOOD
mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)
s3_client.upload_file('file.txt', mrap_arn, 'file.txt')
```

### ❌ ERROR 3: MRAP not ready yet

```python
# Error: MultiRegionAccessPointNotReady
```

**Fix**: Check MRAP status first. MRAP creation can take up to 24 hours:
```python
status = check_mrap_status(ACCOUNT_ID, "my-global-access-point")
if status['status'] == 'READY':
    # Proceed with operations
else:
    print(f"MRAP is {status['status']}, please wait...")
```

## IAM Permissions Required

Your IAM user/role needs these permissions to use MRAP:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS",
        "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS/object/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetMultiRegionAccessPoint",
        "s3:ListMultiRegionAccessPoints"
      ],
      "Resource": "*"
    }
  ]
}
```

## How MRAP Routing Works

When you use MRAP:

1. **Automatic Region Selection**: AWS automatically routes your request to the nearest or lowest-latency bucket
2. **Global Endpoint**: Single endpoint works from anywhere in the world
3. **Replication**: Changes replicate across all regions (within 15 minutes with RTC enabled)
4. **Failover**: If one region is unavailable, requests automatically route to another region

### Example:

```
User in US → MRAP → Routed to us-east-1 bucket (lowest latency)
User in EU → MRAP → Routed to eu-west-1 bucket (lowest latency)
User in Asia → MRAP → Routed to ap-southeast-1 bucket (lowest latency)
```

All users use the same MRAP ARN, but get routed to the optimal region automatically!

## Performance Considerations

- **First Upload**: Uploads to the nearest region
- **Replication**: Takes up to 15 minutes (with RTC enabled) to replicate to other regions
- **Reads**: Always served from the nearest/lowest-latency region
- **Consistency**: Strong consistency within a region, eventual consistency across regions

## Cost Considerations

- **MRAP Request Routing**: Additional charges for routing requests
- **Replication**: Standard cross-region data transfer charges
- **S3 RTC**: Additional cost for Replication Time Control (15-minute guarantee)
- **Storage**: Standard S3 storage costs in each region

## Next Steps

1. Run `terraform apply` to create the MRAP infrastructure
2. Wait up to 24 hours for MRAP to become READY
3. Get the `mrap_alias` from Terraform outputs
4. Update your application code to use the MRAP ARN
5. Test from different regions to verify automatic routing

## Troubleshooting

### Check MRAP Status
```bash
aws s3control get-multi-region-access-point \
  --account-id ACCOUNT_ID \
  --name my-global-access-point
```

### List All MRAPs
```bash
aws s3control list-multi-region-access-points \
  --account-id ACCOUNT_ID
```

### Test MRAP Access
```python
# Run the complete example above
python mrap_example.py
```

## Reference Files

- See `../s3_boto/s3_mrap_example.py` for more detailed examples
- See `main.tf` in this folder for the complete Terraform configuration

```

Perfect! I've created two files in the `mrap/` folder:

## 1. **`main.tf`** - Complete Terraform Configuration

This file includes:
- ✅ **3 S3 buckets** in different regions (us-east-1, eu-west-1, ap-southeast-1)
- ✅ **Versioning enabled** on all buckets (required for MRAP)
- ✅ **Multi-Region Access Point** resource
- ✅ **IAM role and policies** for replication
- ✅ **Bidirectional replication** between all buckets
- ✅ **S3 Replication Time Control (RTC)** for predictable 15-minute replication
- ✅ **Public access blocks** for security
- ✅ **Outputs** for MRAP alias, ARN, and account ID

### To deploy:
```bash
cd mrap/
terraform init
terraform plan
terraform apply
```

⚠️ **Note**: MRAP creation can take up to 24 hours!

## 2. **`BOTO3_CLIENT_CONFIGURATION.md`** - Complete Boto3 Guide

This guide covers:
- ✅ **How to create S3 client** with MRAP configuration (`use_arn_region: True`)
- ✅ **How to construct MRAP ARN** from Terraform outputs
- ✅ **Complete examples** for upload, download, list, presigned URLs
- ✅ **How to check MRAP status** (verify it's READY)
- ✅ **Common errors** and how to fix them
- ✅ **IAM permissions** required
- ✅ **Full working code** you can copy-paste

### Key Configuration:

```python
import boto3
from botocore.config import Config

# CRITICAL: Must enable use_arn_region!
s3_client = boto3.client(
    's3',
    config=Config(
        signature_version='s3v4',
        s3={
            'use_arn_region': True,  # Required for MRAP!
            'addressing_style': 'virtual'
        }
    )
)

# Use MRAP ARN as bucket parameter
mrap_arn = f"arn:aws:s3::{account_id}:accesspoint/{mrap_alias}"
s3_client.upload_file('file.txt', mrap_arn, 'file.txt')
```

Both files are ready to use! The Terraform configuration will create all the infrastructure, and the boto3 guide will show you exactly how to use it in your application. 🚀

```shellscript
cd mrap/
terraform init
terraform plan
terraform apply
```

```python
import boto3
from botocore.config import Config

# CRITICAL: Must enable use_arn_region!
s3_client = boto3.client(
    's3',
    config=Config(
        signature_version='s3v4',
        s3={
            'use_arn_region': True,  # Required for MRAP!
            'addressing_style': 'virtual'
        }
    )
)

# Use MRAP ARN as bucket parameter
mrap_arn = f"arn:aws:s3::{account_id}:accesspoint/{mrap_alias}"
s3_client.upload_file('file.txt', mrap_arn, 'file.txt')
```

---

**User**

i have a bucket in eu-west-2 and another one that i am doing the replication in us-east-2. 
the developers are puting files in the eu-west-2 only. They also create presigned_urls for every object. My purpose is the users that are logged in usa to use the us bucket for the download of the images and the users of europe the european one. Is it possible?

---

**Cursor**

Yes, this is **exactly** what MRAP (Multi-Region Access Point) is designed for! Your use case is perfect for MRAP. Let me explain how it works and create a customized configuration for your specific setup.

## Your Use Case: Perfect for MRAP

**Current Setup:**
- 📦 `eu-west-2` bucket (developers upload here)
- 📦 `us-east-2` bucket (replication target)
- 🔗 Presigned URLs generated for objects

**Goal:**
- 🇪🇺 European users → download from `eu-west-2`
- 🇺🇸 US users → download from `us-east-2`
- ⚡ Automatic routing without application logic

**Solution: MRAP** ✅

With MRAP, you create **ONE presigned URL** using the MRAP ARN, and AWS **automatically routes** users to the nearest bucket!

Let me create updated Terraform and boto3 configurations for your specific case:

```plaintext
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

```

```markdown
# Boto3 Configuration for MRAP with Presigned URLs

## Your Use Case: Automatic Geographic Routing

**Current Setup:**
- 📦 Developers upload images to `eu-west-2` bucket
- 📦 Images replicate to `us-east-2` bucket
- 🔗 Developers create presigned URLs for downloads

**Problem:**
- All users download from same bucket (usually `eu-west-2`)
- US users experience higher latency
- Manually routing users is complex

**Solution with MRAP:**
- ✅ Generate **ONE presigned URL** using MRAP ARN
- ✅ European users automatically download from `eu-west-2`
- ✅ US users automatically download from `us-east-2`
- ✅ No application logic needed - AWS handles routing!

---

## Prerequisites

After running `terraform apply`, you'll have:
- ✅ Versioning enabled on both buckets
- ✅ Replication from `eu-west-2` → `us-east-2`
- ✅ Multi-Region Access Point created

**Get these from Terraform outputs:**
```bash
terraform output mrap_alias      # e.g., "abc123xyz.mrap"
terraform output account_id      # e.g., "123456789012"
terraform output boto3_mrap_arn  # The complete ARN to use
```

---

## Step 1: Update Your S3 Client Configuration

**CRITICAL**: You MUST enable `use_arn_region` for MRAP to work!

```python
import boto3
from botocore.config import Config

def create_s3_client_with_mrap():
    """
    Create S3 client that supports MRAP.
    
    ⚠️ IMPORTANT: Must enable use_arn_region!
    """
    return boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,      # REQUIRED for MRAP!
                'addressing_style': 'virtual'
            }
        )
    )
```

---

## Step 2: Change How You Generate Presigned URLs

This is the **main change** developers need to make!

### ❌ OLD WAY (Bucket-Specific URLs)

```python
# OLD: Direct bucket presigned URL
s3_client = boto3.client('s3')

# This always downloads from eu-west-2, even for US users!
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={
        'Bucket': 'my-bucket-eu-west-2',  # Hardcoded bucket
        'Key': 'images/photo.jpg'
    },
    ExpiresIn=3600
)
# Result: https://my-bucket-eu-west-2.s3.eu-west-2.amazonaws.com/images/photo.jpg?...
# ❌ Problem: US users get slow downloads from EU bucket
```

### ✅ NEW WAY (MRAP URLs - Automatic Routing)

```python
# NEW: MRAP presigned URL with automatic routing
from botocore.config import Config
import boto3

# Step 1: Create MRAP-enabled client
s3_client = boto3.client(
    's3',
    config=Config(
        signature_version='s3v4',
        s3={'use_arn_region': True}  # REQUIRED!
    )
)

# Step 2: Get MRAP ARN from Terraform output
ACCOUNT_ID = "123456789012"      # terraform output account_id
MRAP_ALIAS = "abc123xyz.mrap"    # terraform output mrap_alias
mrap_arn = f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"

# Step 3: Generate presigned URL using MRAP ARN
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={
        'Bucket': mrap_arn,  # Use MRAP ARN instead of bucket name!
        'Key': 'images/photo.jpg'
    },
    ExpiresIn=3600
)
# Result: https://abc123xyz.mrap.accesspoint.s3-global.amazonaws.com/images/photo.jpg?...
# ✅ Benefit: AWS automatically routes users to nearest bucket!
```

---

## Step 3: Complete Developer Code Example

Here's the complete code your developers need to use:

```python
#!/usr/bin/env python3
"""
Example: Generate presigned URLs with MRAP for automatic geographic routing

Usage:
    1. Developer uploads image to eu-west-2 (as before)
    2. Developer generates presigned URL using MRAP ARN
    3. EU users → download from eu-west-2 (low latency)
    4. US users → download from us-east-2 (low latency)
"""
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# Configuration (from Terraform outputs)
# ============================================================================

ACCOUNT_ID = "123456789012"      # terraform output account_id
MRAP_ALIAS = "abc123xyz.mrap"    # terraform output mrap_alias

# Or get the complete ARN directly
# MRAP_ARN = "arn:aws:s3::123456789012:accesspoint/abc123xyz.mrap"

# ============================================================================
# S3 Client Configuration
# ============================================================================

def create_s3_client():
    """
    Create S3 client configured for MRAP operations.
    
    This client can:
    - Upload to regular buckets (eu-west-2)
    - Generate presigned URLs using MRAP ARN
    """
    return boto3.client(
        's3',
        region_name='eu-west-2',  # Default region for uploads
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,      # Required for MRAP!
                'addressing_style': 'virtual'
            }
        )
    )

def get_mrap_arn():
    """Get MRAP ARN from configuration"""
    return f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"

# ============================================================================
# Developer Functions
# ============================================================================

def upload_image(bucket_name, image_path, object_key):
    """
    Upload image to EU bucket (as before).
    
    Developers continue uploading to eu-west-2.
    Replication happens automatically to us-east-2.
    
    Args:
        bucket_name: 'my-bucket-eu-west-2'
        image_path: Local file path to upload
        object_key: S3 key (e.g., 'images/photo.jpg')
    """
    s3_client = create_s3_client()
    
    try:
        s3_client.upload_file(
            Filename=image_path,
            Bucket=bucket_name,  # Still upload to specific bucket
            Key=object_key,
            ExtraArgs={
                'ContentType': 'image/jpeg',  # Set appropriate content type
                'CacheControl': 'max-age=31536000'  # Optional: caching
            }
        )
        logger.info(f"✓ Uploaded {image_path} to {bucket_name}/{object_key}")
        logger.info(f"  Replication to us-east-2 will complete within 15 minutes")
        return True
    except ClientError as e:
        logger.error(f"Error uploading: {e}")
        return False

def generate_presigned_url_with_mrap(object_key, expiration=3600):
    """
    Generate presigned URL using MRAP for automatic geographic routing.
    
    This is the KEY CHANGE for developers!
    
    Args:
        object_key: S3 key (e.g., 'images/photo.jpg')
        expiration: URL expiration in seconds (default: 1 hour)
    
    Returns:
        str: Presigned URL that automatically routes to nearest region
    
    Example:
        >>> url = generate_presigned_url_with_mrap('images/photo.jpg')
        >>> # EU user clicks URL → downloads from eu-west-2
        >>> # US user clicks URL → downloads from us-east-2
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': mrap_arn,  # Use MRAP ARN, not bucket name!
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        
        logger.info(f"✓ Generated presigned URL for {object_key}")
        logger.info(f"  URL: {presigned_url}")
        logger.info(f"  This URL will automatically route users to nearest region:")
        logger.info(f"    - EU users → eu-west-2")
        logger.info(f"    - US users → us-east-2")
        
        return presigned_url
    
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        raise

def generate_presigned_url_for_upload(object_key, expiration=3600):
    """
    Generate presigned URL for uploads using MRAP.
    
    Optional: If you want users to upload directly.
    
    Args:
        object_key: S3 key where user will upload
        expiration: URL expiration in seconds
    
    Returns:
        str: Presigned upload URL
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': mrap_arn,
                'Key': object_key,
                'ContentType': 'image/jpeg'
            },
            ExpiresIn=expiration
        )
        
        logger.info(f"✓ Generated upload presigned URL for {object_key}")
        return presigned_url
    
    except ClientError as e:
        logger.error(f"Error generating upload URL: {e}")
        raise

# ============================================================================
# Example Usage: Typical Developer Workflow
# ============================================================================

def developer_workflow_example():
    """
    Complete example of developer workflow with MRAP.
    """
    
    # Configuration
    EU_BUCKET = "my-bucket-eu-west-2"
    IMAGE_PATH = "./photo.jpg"
    OBJECT_KEY = "images/user123/profile.jpg"
    
    # Step 1: Developer uploads image to EU bucket (as before)
    logger.info("Step 1: Uploading image to eu-west-2...")
    upload_success = upload_image(EU_BUCKET, IMAGE_PATH, OBJECT_KEY)
    
    if not upload_success:
        logger.error("Upload failed!")
        return
    
    # Step 2: Generate presigned URL using MRAP (NEW!)
    logger.info("\nStep 2: Generating presigned URL with MRAP...")
    presigned_url = generate_presigned_url_with_mrap(OBJECT_KEY, expiration=3600)
    
    # Step 3: Return URL to application/users
    logger.info("\nStep 3: Use this URL in your application:")
    logger.info(f"  URL: {presigned_url}")
    logger.info("\n✓ Done! Users will automatically download from nearest region:")
    logger.info("  - EU users: eu-west-2 (low latency)")
    logger.info("  - US users: us-east-2 (low latency)")
    
    return presigned_url

# ============================================================================
# Batch Processing Example
# ============================================================================

def generate_presigned_urls_batch(object_keys, expiration=3600):
    """
    Generate presigned URLs for multiple objects.
    
    Useful for: gallery views, listing pages, etc.
    
    Args:
        object_keys: List of S3 keys
        expiration: URL expiration in seconds
    
    Returns:
        dict: Mapping of object_key → presigned_url
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    urls = {}
    
    for key in object_keys:
        try:
            url = s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': mrap_arn, 'Key': key},
                ExpiresIn=expiration
            )
            urls[key] = url
            logger.info(f"✓ Generated URL for {key}")
        except ClientError as e:
            logger.error(f"Failed to generate URL for {key}: {e}")
            urls[key] = None
    
    return urls

# ============================================================================
# Comparison: Old vs New
# ============================================================================

def compare_old_vs_new(object_key):
    """
    Show the difference between old and new approach.
    """
    s3_client_old = boto3.client('s3', region_name='eu-west-2')
    s3_client_new = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    print("=" * 80)
    print("COMPARISON: Old vs New Presigned URL Generation")
    print("=" * 80)
    
    # Old way
    print("\n❌ OLD WAY (bucket-specific):")
    old_url = s3_client_old.generate_presigned_url(
        'get_object',
        Params={'Bucket': 'my-bucket-eu-west-2', 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {old_url}")
    print("Result: ALL users download from eu-west-2")
    print("  - EU users: Low latency ✓")
    print("  - US users: High latency ✗")
    
    # New way
    print("\n✅ NEW WAY (MRAP with automatic routing):")
    new_url = s3_client_new.generate_presigned_url(
        'get_object',
        Params={'Bucket': mrap_arn, 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {new_url}")
    print("Result: Users download from NEAREST region (automatic!)")
    print("  - EU users: Download from eu-west-2 (low latency) ✓")
    print("  - US users: Download from us-east-2 (low latency) ✓")
    
    print("\n" + "=" * 80)

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    print("\n🌍 MRAP Presigned URLs - Geographic Routing Example\n")
    
    # Example 1: Complete developer workflow
    print("Example 1: Complete Developer Workflow")
    print("-" * 80)
    # developer_workflow_example()
    
    # Example 2: Just generate presigned URL for existing object
    print("\n\nExample 2: Generate Presigned URL (existing object)")
    print("-" * 80)
    # url = generate_presigned_url_with_mrap('images/photo.jpg')
    # print(f"Presigned URL: {url}")
    
    # Example 3: Batch generate URLs
    print("\n\nExample 3: Batch Generate URLs")
    print("-" * 80)
    # image_keys = ['images/img1.jpg', 'images/img2.jpg', 'images/img3.jpg']
    # urls = generate_presigned_urls_batch(image_keys)
    # for key, url in urls.items():
    #     print(f"{key}: {url}")
    
    # Example 4: Compare old vs new
    print("\n\nExample 4: Compare Old vs New Approach")
    print("-" * 80)
    # compare_old_vs_new('images/photo.jpg')
    
    print("\n✓ Examples ready. Uncomment the examples you want to test.\n")
```

---

## Step 4: Test the Configuration

### Check MRAP Status

```python
import boto3

def check_mrap_status(account_id, mrap_name):
    """
    Check if MRAP is ready (can take up to 24 hours).
    
    Args:
        account_id: Your AWS account ID
        mrap_name: MRAP name from terraform (e.g., 'my-global-access-point')
    """
    s3control = boto3.client('s3control')
    
    response = s3control.get_multi_region_access_point(
        AccountId=account_id,
        Name=mrap_name
    )
    
    status = response['AccessPoint']['Status']
    alias = response['AccessPoint'].get('Alias', 'N/A')
    
    print(f"MRAP Name: {mrap_name}")
    print(f"Status: {status}")
    print(f"Alias: {alias}")
    
    if status == 'READY':
        print("✓ MRAP is READY! You can start using it.")
    else:
        print(f"⚠️ MRAP is {status}. Please wait (can take up to 24 hours).")
    
    return status, alias

# Usage
check_mrap_status("123456789012", "my-global-access-point")
```

### Test Upload and Download Flow

```python
def test_mrap_flow():
    """
    Test complete flow: upload → replicate → generate presigned URL
    """
    import time
    
    EU_BUCKET = "my-bucket-eu-west-2"
    TEST_KEY = "test/mrap-test.txt"
    TEST_CONTENT = b"Testing MRAP automatic routing!"
    
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    # 1. Upload to EU bucket
    print("1. Uploading test file to eu-west-2...")
    s3_client.put_object(
        Bucket=EU_BUCKET,
        Key=TEST_KEY,
        Body=TEST_CONTENT
    )
    print("✓ Upload complete")
    
    # 2. Wait for replication (usually takes a few minutes)
    print("\n2. Waiting 30 seconds for replication to us-east-2...")
    time.sleep(30)
    
    # 3. Generate MRAP presigned URL
    print("\n3. Generating presigned URL with MRAP...")
    url = s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': mrap_arn, 'Key': TEST_KEY},
        ExpiresIn=300
    )
    print(f"✓ Presigned URL: {url}")
    
    # 4. Test download via MRAP
    print("\n4. Testing download via MRAP...")
    response = s3_client.get_object(Bucket=mrap_arn, Key=TEST_KEY)
    content = response['Body'].read()
    
    if content == TEST_CONTENT:
        print("✓ Download successful!")
        print(f"  Content: {content.decode('utf-8')}")
        print("\n✓ MRAP is working correctly!")
    else:
        print("✗ Content mismatch!")
    
    print("\n" + "=" * 80)
    print("You can now use MRAP presigned URLs in production!")
    print("Users will automatically download from nearest region.")
    print("=" * 80)

# Run test
# test_mrap_flow()
```

---

## Migration Strategy for Developers

### Phase 1: Preparation (Before Terraform Apply)

1. ✅ Review current code that generates presigned URLs
2. ✅ Identify all places where `generate_presigned_url` is called
3. ✅ Plan code changes

### Phase 2: Infrastructure (Terraform)

```bash
cd mrap/
terraform init
terraform plan
terraform apply
```

Wait up to 24 hours for MRAP to become READY.

### Phase 3: Code Migration

**Create helper module** (e.g., `s3_utils.py`):

```python
# s3_utils.py
import boto3
from botocore.config import Config
import os

# Configuration (from environment or config file)
ACCOUNT_ID = os.getenv('AWS_ACCOUNT_ID', '123456789012')
MRAP_ALIAS = os.getenv('MRAP_ALIAS', 'abc123xyz.mrap')
USE_MRAP = os.getenv('USE_MRAP', 'true').lower() == 'true'

def get_s3_client():
    """Get S3 client with MRAP support"""
    return boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={'use_arn_region': True}
        )
    )

def get_bucket_or_mrap_arn(bucket_name):
    """
    Return MRAP ARN if enabled, otherwise return bucket name.
    
    This allows gradual migration!
    """
    if USE_MRAP:
        return f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"
    else:
        return bucket_name

def generate_download_url(object_key, expiration=3600):
    """
    Generate presigned URL for download.
    
    Uses MRAP if enabled, otherwise falls back to direct bucket access.
    """
    s3_client = get_s3_client()
    bucket = get_bucket_or_mrap_arn('my-bucket-eu-west-2')
    
    return s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket, 'Key': object_key},
        ExpiresIn=expiration
    )
```

**Update application code:**

```python
# Before
from old_s3_utils import generate_url
url = generate_url('images/photo.jpg')

# After (same interface!)
from s3_utils import generate_download_url
url = generate_download_url('images/photo.jpg')
```

### Phase 4: Testing

1. Enable MRAP: `USE_MRAP=true`
2. Test from different locations (EU and US)
3. Verify automatic routing works
4. Monitor CloudWatch metrics

### Phase 5: Rollout

1. Deploy code changes (with MRAP disabled initially)
2. Enable MRAP via environment variable
3. Monitor for issues
4. Rollback if needed (change `USE_MRAP=false`)

---

## FAQ

### Q: Do uploads also route automatically?

**A:** Yes! If you upload using MRAP ARN, AWS routes to the nearest region. However, for your use case, you can continue uploading directly to `eu-west-2` and only use MRAP for presigned URLs.

```python
# Option 1: Upload to specific bucket (current approach - works fine)
s3_client.upload_file('photo.jpg', 'my-bucket-eu-west-2', 'images/photo.jpg')

# Option 2: Upload via MRAP (also works - routes automatically)
s3_client.upload_file('photo.jpg', mrap_arn, 'images/photo.jpg')
```

### Q: How long does replication take?

**A:** With S3 Replication Time Control (RTC) enabled in Terraform, replication completes within 15 minutes. Without RTC, it usually takes minutes but is not guaranteed.

### Q: What if the US bucket doesn't have the object yet?

**A:** MRAP is smart! If a user requests an object that hasn't replicated yet, MRAP will fetch it from the source bucket (eu-west-2) and serve it. Once replication completes, future requests use the local copy.

### Q: Can I still access buckets directly?

**A:** Yes! Direct bucket access still works. MRAP is additive - it doesn't break existing access patterns.

### Q: What about object metadata and permissions?

**A:** Replication copies everything: object data, metadata, tags, and ACLs (if configured). Presigned URLs work the same way whether using bucket name or MRAP ARN.

### Q: What's the cost impact?

**A:** 
- MRAP routing: ~$0.0005 per 1,000 requests
- Replication: Standard cross-region transfer costs (~$0.02/GB)
- S3 RTC: Additional ~$0.015/GB

For most use cases, the improved user experience justifies the cost.

---

## Troubleshooting

### Error: "The ARN is not supported for this operation"

**Cause:** Missing `use_arn_region: True` in client config

**Fix:**
```python
s3_client = boto3.client(
    's3',
    config=Config(s3={'use_arn_region': True})
)
```

### Error: "MultiRegionAccessPointNotReady"

**Cause:** MRAP is still being created (can take up to 24 hours)

**Fix:** Check status:
```bash
terraform output mrap_status
```

Wait until status is `READY`.

### Presigned URLs return 403 Forbidden

**Cause:** IAM permissions issue

**Fix:** Ensure your IAM user/role has:
```json
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS/object/*"
}
```

### Objects not replicating

**Check:**
1. Is versioning enabled? `terraform output bucket_names` then check versioning
2. Is replication rule active? Check AWS Console → S3 → Bucket → Replication
3. Check CloudWatch metrics for replication lag

---

## Summary

**Key Changes for Developers:**

1. ✅ Use `create_s3_client()` with `use_arn_region: True`
2. ✅ Use MRAP ARN instead of bucket name in presigned URLs
3. ✅ Everything else stays the same!

**Result:**
- 🇪🇺 European users: Fast downloads from `eu-west-2`
- 🇺🇸 US users: Fast downloads from `us-east-2`
- 🌍 Automatic routing based on user location
- 🎯 One presigned URL works for everyone!

**Next Steps:**
1. Wait for `terraform apply` to complete (up to 24 hours)
2. Get MRAP alias from `terraform output`
3. Update code to use MRAP ARN
4. Test and deploy!

```

```plaintext
# ============================================================================
# Terraform Variables Configuration for MRAP
# ============================================================================
#
# 1. Copy this file to terraform.tfvars:
#    cp terraform.tfvars.example terraform.tfvars
#
# 2. Update the values below with your bucket names
#
# 3. Run terraform:
#    terraform init
#    terraform plan
#    terraform apply
#
# ============================================================================

# Name for your Multi-Region Access Point (must be unique in your AWS account)
mrap_name = "my-global-access-point"

# Your existing or new bucket in EU (eu-west-2)
eu_bucket_name = "my-bucket-eu-west-2"

# Your existing or new bucket in US (us-east-2)
us_bucket_name = "my-bucket-us-east-2"

# Set to false if your buckets already exist
# Set to true if you want Terraform to create new buckets
create_buckets = true

# Enable S3 Replication Time Control for guaranteed 15-minute replication
# Costs extra but provides predictable replication time
enable_replication_time_control = true

# Optional: Add custom tags
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Purpose     = "mrap-global-access"
  Team        = "platform"
}

```

```markdown
# Multi-Region Access Point (MRAP) Configuration

This directory contains Terraform configuration to set up MRAP for automatic geographic routing of S3 downloads.

## 🎯 Use Case

**Problem:**
- Developers upload images to `eu-west-2` bucket
- Images replicate to `us-east-2` bucket
- All users download from same bucket → high latency for distant users

**Solution:**
- ✅ Generate ONE presigned URL using MRAP
- ✅ European users automatically download from `eu-west-2` (low latency)
- ✅ US users automatically download from `us-east-2` (low latency)
- ✅ No application logic needed!

## 📁 Files

- **`main.tf`** - Complete Terraform configuration for MRAP
- **`BOTO3_CLIENT_CONFIGURATION.md`** - Developer guide for boto3 code changes
- **`terraform.tfvars.example`** - Example configuration file
- **`README.md`** - This file

## 🚀 Quick Start

### Step 1: Configure Terraform

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your bucket names
vim terraform.tfvars
```

Update these values in `terraform.tfvars`:

```hcl
mrap_name = "my-global-access-point"
eu_bucket_name = "my-bucket-eu-west-2"  # Your EU bucket
us_bucket_name = "my-bucket-us-east-2"  # Your US bucket
create_buckets = false  # Set to false if buckets already exist
```

### Step 2: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply configuration
terraform apply
```

⚠️ **IMPORTANT:** MRAP creation can take up to 24 hours!

### Step 3: Get Configuration Values

After `terraform apply` completes, get the values you need:

```bash
# Get MRAP alias (needed for boto3)
terraform output mrap_alias

# Get your AWS Account ID
terraform output account_id

# Get complete MRAP ARN (ready to use in code)
terraform output boto3_mrap_arn

# See complete developer instructions
terraform output developer_instructions
```

### Step 4: Update Developer Code

See **`BOTO3_CLIENT_CONFIGURATION.md`** for complete code examples.

**Quick summary:**

```python
# OLD: Bucket-specific presigned URLs
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket-eu-west-2', 'Key': 'image.jpg'})

# NEW: MRAP presigned URLs (automatic routing!)
mrap_arn = "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS"  # From terraform output
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': mrap_arn, 'Key': 'image.jpg'})
```

## 📊 What Gets Created

1. **Versioning** enabled on both buckets (required for MRAP)
2. **S3 Replication** from eu-west-2 → us-east-2 (automatic)
3. **Multi-Region Access Point** spanning both regions
4. **IAM Role** for replication with appropriate permissions
5. **Public Access Blocks** for security best practices

## 🔍 Check MRAP Status

MRAP creation can take up to 24 hours. Check status:

```bash
# Via Terraform
terraform output mrap_status

# Via AWS CLI
aws s3control get-multi-region-access-point \
  --account-id YOUR_ACCOUNT_ID \
  --name my-global-access-point
```

Status will be one of:
- `CREATING` - Still being created (wait)
- `READY` - Ready to use! ✅
- `UPDATING` - Configuration change in progress
- `DELETING` - Being deleted

## 🌍 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Workflow                        │
└─────────────────────────────────────────────────────────────┘
    │
    │ 1. Upload to eu-west-2
    ├────────────────────────────►  ┌──────────────────┐
    │                               │  eu-west-2       │
    │ 2. Generate presigned URL     │  Bucket          │
    │    using MRAP ARN             └──────────────────┘
    │                                      │
    │                                      │ Replication
    │                                      │ (within 15 min)
    │                                      ▼
    │                               ┌──────────────────┐
    │                               │  us-east-2       │
    │                               │  Bucket          │
    │                               └──────────────────┘
    │
    │ 3. User clicks presigned URL
    ▼
┌─────────────────────────────────────────────────────────────┐
│                    MRAP Automatic Routing                    │
└─────────────────────────────────────────────────────────────┘
    │
    ├─► EU User    ──► Routes to eu-west-2  (low latency ✅)
    │
    └─► US User    ──► Routes to us-east-2  (low latency ✅)
```

## 💰 Cost Considerations

| Component | Cost | Notes |
|-----------|------|-------|
| MRAP Routing | ~$0.0005 per 1,000 requests | Charged per request routed |
| S3 Replication | ~$0.02/GB | Standard cross-region transfer |
| S3 RTC | ~$0.015/GB | Optional, guarantees 15-min replication |
| Storage | Standard S3 pricing | Charged in both regions |

**Estimated monthly cost** for 1TB data with 1M downloads:
- Without MRAP: ~$0 (but poor UX for US users)
- With MRAP: ~$30-50 (great UX for all users)

## 🔐 Security

- ✅ Public access blocked on all buckets
- ✅ IAM roles follow least-privilege principle
- ✅ Versioning enabled (protects against accidental deletes)
- ✅ Presigned URLs support same security as regular S3
- ✅ MRAP respects existing bucket policies

## 📈 Monitoring

### Check Replication Status

```bash
# Via AWS CLI
aws s3api get-bucket-replication \
  --bucket my-bucket-eu-west-2
```

### CloudWatch Metrics

Monitor these metrics:
- `ReplicationLatency` - Time to replicate objects
- `BytesPendingReplication` - Data waiting to replicate
- `OperationsPendingReplication` - Objects waiting to replicate

### Test Replication

```python
import boto3
import time

s3 = boto3.client('s3', region_name='eu-west-2')
s3_us = boto3.client('s3', region_name='us-east-2')

# Upload to EU
s3.put_object(Bucket='my-bucket-eu-west-2', Key='test.txt', Body=b'test')

# Wait a bit
time.sleep(30)

# Check if replicated to US
try:
    s3_us.head_object(Bucket='my-bucket-us-east-2', Key='test.txt')
    print("✓ Replication working!")
except:
    print("✗ Not yet replicated (wait longer)")
```

## 🐛 Troubleshooting

### MRAP Status Stuck on CREATING

**Normal!** MRAP creation can take up to 24 hours. Check periodically:

```bash
watch -n 300 'terraform output mrap_status'  # Check every 5 minutes
```

### Objects Not Replicating

1. ✅ Check versioning is enabled:
   ```bash
   aws s3api get-bucket-versioning --bucket my-bucket-eu-west-2
   ```

2. ✅ Check replication rule is active:
   ```bash
   aws s3api get-bucket-replication --bucket my-bucket-eu-west-2
   ```

3. ✅ Check CloudWatch metrics for replication lag

### Presigned URLs Return 403

1. ✅ Check MRAP status is `READY`
2. ✅ Verify IAM permissions include MRAP access
3. ✅ Ensure boto3 client has `use_arn_region: True`

### Error: "The ARN is not supported for this operation"

**Fix:** Enable `use_arn_region` in boto3 config:

```python
from botocore.config import Config
import boto3

s3 = boto3.client('s3', config=Config(s3={'use_arn_region': True}))
```

## 🔄 Updates and Changes

### Changing MRAP Configuration

```bash
# Update terraform.tfvars with new values
vim terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

### Adding More Regions

Edit `main.tf` and add additional buckets and replication rules. For example, to add `ap-southeast-1`:

1. Add provider for new region
2. Add bucket resource
3. Add versioning resource
4. Add replication rules
5. Add region to MRAP configuration

### Removing MRAP

```bash
# This will destroy MRAP but keep buckets
terraform destroy

# Warning: MRAP deletion can also take several hours!
```

## 📚 Additional Resources

- **`BOTO3_CLIENT_CONFIGURATION.md`** - Complete developer guide
- [AWS MRAP Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPoints.html)
- [S3 Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [S3 Presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)

## ❓ FAQ

**Q: Can developers still upload directly to eu-west-2?**  
A: Yes! Uploads work exactly as before. MRAP is only for generating presigned URLs.

**Q: What happens if an object hasn't replicated yet?**  
A: MRAP automatically fetches from the source region (eu-west-2) until replication completes.

**Q: Do we need to change our upload code?**  
A: No! Only presigned URL generation needs to change. See `BOTO3_CLIENT_CONFIGURATION.md`.

**Q: Can we test before going to production?**  
A: Yes! Use environment variables to toggle between MRAP and direct bucket access.

**Q: What if we want to add more regions later?**  
A: Easy! Just edit `main.tf` to add more buckets and update the MRAP configuration.

## 🎉 Success Criteria

After deployment, you should have:

- ✅ MRAP status is `READY`
- ✅ Objects replicate from eu-west-2 → us-east-2 within 15 minutes
- ✅ Presigned URLs work from both regions
- ✅ EU users download from eu-west-2 (verify with VPN/proxy)
- ✅ US users download from us-east-2 (verify with VPN/proxy)
- ✅ CloudWatch metrics show successful replication

## 📞 Support

For issues:
1. Check `BOTO3_CLIENT_CONFIGURATION.md` for code examples
2. Review troubleshooting section above
3. Check AWS CloudWatch for replication metrics
4. Verify MRAP status with `terraform output mrap_status`

---

**Ready to get started?**

```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 2. Deploy
terraform init
terraform apply

# 3. Wait for MRAP to become READY (up to 24 hours)
terraform output mrap_status

# 4. Update developer code (see BOTO3_CLIENT_CONFIGURATION.md)
```

🚀 Your users will thank you for the improved download speeds!

```

Perfect! I've created a complete MRAP solution specifically for your use case. Here's what you now have in the `mrap/` folder:

## 📁 Created Files

### 1. **`main.tf`** - Terraform Configuration
- Configured for **eu-west-2** (primary) and **us-east-2** (replica)
- Handles both existing and new buckets
- Automatic replication from EU → US
- S3 Replication Time Control (15-minute guarantee)
- Complete IAM roles and permissions

### 2. **`BOTO3_CLIENT_CONFIGURATION.md`** - Developer Guide
- Complete code examples for presigned URLs with MRAP
- **Before/After comparison** showing exactly what to change
- Step-by-step migration guide
- Testing and troubleshooting tips
- Real-world examples your developers can copy-paste

### 3. **`terraform.tfvars.example`** - Configuration Template
- Easy-to-fill configuration file
- Just copy and update with your bucket names

### 4. **`README.md`** - Complete Documentation
- Quick start guide
- Architecture diagram
- Cost estimates
- Monitoring and troubleshooting

## 🎯 How This Solves Your Problem

**Your Current Situation:**
- ✅ Developers upload to `eu-west-2`
- ✅ Replication to `us-east-2`
- ❌ All users download from `eu-west-2` (slow for US users)

**With MRAP:**
- ✅ Developers still upload to `eu-west-2` (no change!)
- ✅ Generate **ONE presigned URL** using MRAP ARN
- ✅ EU users → automatically download from `eu-west-2`
- ✅ US users → automatically download from `us-east-2`
- ✅ **No application logic needed** - AWS handles routing!

## 🚀 Quick Start

```bash
cd mrap/

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit with your bucket names

# 2. Deploy
terraform init
terraform apply

# 3. Get MRAP ARN (after ~24 hours when ready)
terraform output boto3_mrap_arn
```

## 📝 Code Change for Developers

**Only one change needed** - in presigned URL generation:

```python
# OLD (all users download from EU)
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket-eu-west-2', 'Key': 'image.jpg'})

# NEW (automatic routing to nearest region!)
mrap_arn = "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS"
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': mrap_arn, 'Key': 'image.jpg'})
```

That's it! Everything else stays the same.

## ✅ Answer to Your Question

**"Is it possible for US users to download from US bucket and EU users from EU bucket?"**

**YES!** MRAP does exactly this automatically. You:
1. Generate ONE presigned URL with MRAP ARN
2. Give it to all users
3. AWS automatically routes each user to their nearest bucket
4. No location detection or multiple URLs needed!

The complete documentation in `BOTO3_CLIENT_CONFIGURATION.md` has everything your developers need with copy-paste examples. 🎉

```shellscript
cd mrap/

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit with your bucket names

# 2. Deploy
terraform init
terraform apply

# 3. Get MRAP ARN (after ~24 hours when ready)
terraform output boto3_mrap_arn
```

```python
# OLD (all users download from EU)
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket-eu-west-2', 'Key': 'image.jpg'})

# NEW (automatic routing to nearest region!)
mrap_arn = "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS"
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': mrap_arn, 'Key': 'image.jpg'})
```

