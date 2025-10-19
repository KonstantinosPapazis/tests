# Configure s3 replication with terragrunt
_Exported on 10/19/2025 at 20:50:41 GMT+2 from Cursor (1.7.52)_

---

**User**

in my comoany they are using terragrunt. The structure of the folders is repo_name/environment/region/service/terragrunt.hcl

So i have cloud_repo/dev/eu-west-2/s3/terragrunt.hcl and then i have cloud_repo/dev/us-west-2/s3/terragrunt.hcl

In each terragrunt file there is the terraform module that is used and as input they pass all variables.

Now i have a task to create s3 replication between the 2 buckets on the above regions. The s3 replication requires the s3 name of the bucket in the other region as well as the KMS ARN. How can i pass the variables in the eu-west-2 from the bucket and kms of us-west-2?

---

**Cursor**

I'd be happy to help you set up cross-region S3 replication in Terragrunt! This is a common pattern where you need to reference outputs from one region's resources as inputs to another region.

Let me first check if you have any existing Terragrunt configuration in your workspace to better understand your setup.

Since your workspace is empty, I need to clarify what you'd like me to help you with:

1. Would you like me to:
   - a) Create example Terragrunt configurations demonstrating the cross-region dependency pattern?
   - b) Explain the approach(es) conceptually without creating files?

2. For the Terraform module being used in your terragrunt.hcl files:
   - a) Is it a custom internal module that you control?
   - b) Is it a community module (e.g., from Terraform Registry)?

3. Do the current Terraform modules already output the bucket name and KMS ARN?
   - a) Yes, they already have outputs defined
   - b) No, we'll need to add outputs
   - c) Not sure

These answers will help me provide the most relevant solution for your S3 replication setup.

---

**User**

1 a
2 a
3 a

Every region configuration is stored on another path terraform state

---

**Cursor**

Perfect! Now I understand your setup. Since each region has its own Terraform state, you'll need to use Terragrunt's `dependency` blocks to reference outputs from one region in another.

Let me create a comprehensive example demonstrating how to handle cross-region S3 replication with Terragrunt dependencies.

---

**User**

Implement the plan as specified. To-do's from the plan have already been created, do not create them again.

---

**Cursor**

Perfect! Let me implement the cross-region S3 replication setup with Terragrunt. I'll create the complete example structure.

```plaintext
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
    {
      Name = "${var.bucket_name}-kms-key"
    }
  )
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.s3.key_id
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
        Resource = var.replication_destination_kms_arn
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
        replica_kms_key_id = var.replication_destination_kms_arn
      }
    }
  }
}

```

```plaintext
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_replication" {
  description = "Enable S3 replication to another region"
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination bucket for replication"
  type        = string
  default     = ""
}

variable "replication_destination_kms_arn" {
  description = "ARN of the destination KMS key for replication"
  type        = string
  default     = ""
}

variable "replication_storage_class" {
  description = "Storage class for replicated objects"
  type        = string
  default     = "STANDARD"
}

```

```plaintext
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

```

```plaintext
terraform {
  source = "../../../modules/s3"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependency on eu-west-2 bucket for bi-directional replication
# If you only want one-way replication (eu-west-2 -> us-west-2), you can add this dependency
# For the initial setup, you might want to comment this out and apply us-west-2 first
dependency "eu_west_2" {
  config_path = "../../eu-west-2/s3"
  
  # Mock outputs allow terragrunt to run plan/apply even if dependency doesn't exist yet
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::mock-eu-west-2-bucket"
    kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/mock-key-id"
  }
  
  # Set to false if you want strict dependency (won't work until eu-west-2 is applied)
  skip_outputs = false
}

inputs = {
  bucket_name = "my-company-us-west-2-bucket-dev"
  
  # Enable replication to eu-west-2
  enable_replication = true
  replication_destination_bucket_arn = dependency.eu_west_2.outputs.bucket_arn
  replication_destination_kms_arn    = dependency.eu_west_2.outputs.kms_key_arn
  replication_storage_class          = "STANDARD"
  
  kms_deletion_window = 30
  
  tags = {
    Environment = "dev"
    Region      = "us-west-2"
    ManagedBy   = "Terragrunt"
    Service     = "s3-replication"
  }
}

```

```plaintext
terraform {
  source = "../../../modules/s3"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependency on us-west-2 bucket to get its ARN and KMS key for replication
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
  
  # Mock outputs allow terragrunt to run plan/apply even if dependency doesn't exist yet
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::mock-us-west-2-bucket"
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/mock-key-id"
  }
  
  # Set to false if you want strict dependency (won't work until us-west-2 is applied)
  skip_outputs = false
}

inputs = {
  bucket_name = "my-company-eu-west-2-bucket-dev"
  
  # Enable replication to us-west-2
  enable_replication = true
  replication_destination_bucket_arn = dependency.us_west_2.outputs.bucket_arn
  replication_destination_kms_arn    = dependency.us_west_2.outputs.kms_key_arn
  replication_storage_class          = "STANDARD"
  
  kms_deletion_window = 30
  
  tags = {
    Environment = "dev"
    Region      = "eu-west-2"
    ManagedBy   = "Terragrunt"
    Service     = "s3-replication"
  }
}

```

```plaintext
# Root Terragrunt configuration
# This file contains shared configuration for all environments and regions

locals {
  # Parse the directory structure to extract environment and region
  parsed_path = regex(".*/(.*?)/(.*?)/.*", get_terragrunt_dir())
  environment = local.parsed_path[0]
  region      = local.parsed_path[1]
}

# Configure remote state backend
remote_state {
  backend = "s3"
  
  config = {
    # Customize these values for your AWS account
    bucket         = "my-company-terraform-state-${local.environment}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"  # State bucket region
    encrypt        = true
    dynamodb_table = "my-company-terraform-locks-${local.environment}"
    
    # Optional: S3 bucket versioning and lifecycle
    s3_bucket_tags = {
      Environment = local.environment
      ManagedBy   = "Terragrunt"
    }
  }
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<EOF
provider "aws" {
  region = "${local.region}"
  
  default_tags {
    tags = {
      Environment = "${local.environment}"
      Region      = "${local.region}"
      ManagedBy   = "Terragrunt"
    }
  }
}
EOF
}

# Terraform configuration
terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }
  
  # Automatically retry on common errors
  extra_arguments "retry_lock" {
    commands = get_terraform_commands_that_need_locking()
    
    arguments = [
      "-lock-timeout=5m"
    ]
  }
}

# Input variables available to all modules
inputs = {
  environment = local.environment
  region      = local.region
}

```

```markdown
# Cross-Region S3 Replication with Terragrunt

This repository demonstrates how to set up cross-region S3 replication using Terragrunt's dependency management features.

## Architecture

The setup includes:
- **us-west-2**: Primary S3 bucket with replication to eu-west-2
- **eu-west-2**: Secondary S3 bucket with replication to us-west-2
- **KMS encryption**: Each bucket has its own KMS key
- **Bi-directional replication**: Changes in either bucket replicate to the other

## Directory Structure

```
cloud_repo/
├── terragrunt.hcl                    # Root configuration (shared settings)
├── modules/
│   └── s3/                           # Reusable S3 module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── dev/
    ├── us-west-2/
    │   └── s3/
    │       └── terragrunt.hcl        # US bucket configuration
    └── eu-west-2/
        └── s3/
            └── terragrunt.hcl        # EU bucket configuration
```

## How Terragrunt Dependencies Work

### The Problem
S3 replication requires knowing the destination bucket ARN and KMS key ARN. Since each region's Terraform state is stored separately, we need a way to reference outputs from one region in another.

### The Solution: Dependency Blocks

In `cloud_repo/dev/eu-west-2/s3/terragrunt.hcl`:

```hcl
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
  
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::mock-us-west-2-bucket"
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/mock-key-id"
  }
}

inputs = {
  enable_replication = true
  replication_destination_bucket_arn = dependency.us_west_2.outputs.bucket_arn
  replication_destination_kms_arn    = dependency.us_west_2.outputs.kms_key_arn
}
```

**Key Points:**
1. `config_path`: Relative path to the dependency's terragrunt.hcl
2. `mock_outputs`: Fake values used during plan/init before dependency exists
3. `dependency.<name>.outputs.<output_name>`: Reference actual Terraform outputs

## Deployment Order

### Initial Setup (First Time)

Since we have bi-directional replication, we need to bootstrap the setup:

**Option 1: Deploy without replication first**
```bash
# Step 1: Comment out replication in both terragrunt.hcl files
# Set: enable_replication = false

# Step 2: Deploy both buckets
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

cd ../../../eu-west-2/s3
terragrunt apply

# Step 3: Enable replication in both terragrunt.hcl files
# Set: enable_replication = true

# Step 4: Apply again to enable replication
cd ../../us-west-2/s3
terragrunt apply

cd ../../../eu-west-2/s3
terragrunt apply
```

**Option 2: Use mock outputs and deploy sequentially**
```bash
# Step 1: Deploy us-west-2 first (will use mock outputs for eu-west-2)
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

# Step 2: Deploy eu-west-2 (will use real outputs from us-west-2)
cd ../../../eu-west-2/s3
terragrunt apply

# Step 3: Re-apply us-west-2 to use real eu-west-2 outputs
cd ../../us-west-2/s3
terragrunt apply
```

### Subsequent Updates

After initial setup, you can deploy in any order:

```bash
# Deploy specific region
cd cloud_repo/dev/eu-west-2/s3
terragrunt apply

# Deploy all regions
cd cloud_repo/dev
terragrunt run-all apply
```

## Common Commands

### Plan Changes
```bash
cd cloud_repo/dev/eu-west-2/s3
terragrunt plan
```

### Apply Changes
```bash
cd cloud_repo/dev/eu-west-2/s3
terragrunt apply
```

### Destroy Resources
```bash
cd cloud_repo/dev/eu-west-2/s3
terragrunt destroy
```

### Run All (Parallel Execution)
```bash
# Apply to all regions at once
cd cloud_repo/dev
terragrunt run-all apply

# Plan for all regions
terragrunt run-all plan
```

### View Dependency Graph
```bash
cd cloud_repo/dev
terragrunt graph-dependencies
```

## Customization

### Update Bucket Names
Edit the `bucket_name` input in each region's `terragrunt.hcl`:

```hcl
inputs = {
  bucket_name = "your-custom-bucket-name-us-west-2"
}
```

### Add More Regions
To add another region (e.g., ap-southeast-1):

1. Create directory structure:
   ```bash
   mkdir -p cloud_repo/dev/ap-southeast-1/s3
   ```

2. Copy terragrunt.hcl from an existing region:
   ```bash
   cp cloud_repo/dev/us-west-2/s3/terragrunt.hcl \
      cloud_repo/dev/ap-southeast-1/s3/terragrunt.hcl
   ```

3. Update the dependency config_path and inputs

### One-Way Replication Only
If you only want eu-west-2 → us-west-2 replication:

1. In `us-west-2/s3/terragrunt.hcl`: Set `enable_replication = false` or remove the dependency block
2. In `eu-west-2/s3/terragrunt.hcl`: Keep `enable_replication = true`

## Troubleshooting

### Error: Dependency outputs not found
**Issue**: Terragrunt can't find the outputs from the dependency

**Solution**:
```bash
# Make sure the dependency has been applied
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

# Then try again
cd ../../../eu-west-2/s3
terragrunt apply
```

### Error: Circular dependency
**Issue**: Both regions depend on each other (bi-directional replication)

**Solution**: Use the bootstrap approach (Option 1 or 2 above)

### Mock outputs being used instead of real outputs
**Issue**: Terragrunt is using mock values even though dependency exists

**Solution**:
```bash
# Clear the cache and re-run
rm -rf .terragrunt-cache
terragrunt apply
```

## Remote State Configuration

The root `terragrunt.hcl` configures S3 backend for state storage. Update these values:

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "my-company-terraform-state-${local.environment}"
    region         = "us-east-1"
    dynamodb_table = "my-company-terraform-locks-${local.environment}"
  }
}
```

Make sure to:
1. Create the S3 bucket for state storage
2. Create the DynamoDB table for state locking
3. Update the bucket name and region to match your setup

## Security Considerations

1. **KMS Keys**: Each region has its own KMS key for encryption
2. **IAM Roles**: Replication role has minimal required permissions
3. **Versioning**: Enabled by default (required for replication)
4. **Encryption**: All objects encrypted at rest with KMS

## Module Outputs

The S3 module provides these outputs for cross-region reference:

- `bucket_name`: Name of the S3 bucket
- `bucket_arn`: ARN of the S3 bucket (used in replication config)
- `kms_key_arn`: ARN of the KMS key (used for encryption in replication)
- `kms_key_id`: ID of the KMS key
- `replication_role_arn`: ARN of the replication IAM role

## Additional Resources

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
- [Terragrunt Dependencies](https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#dependency)
- [AWS S3 Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [AWS S3 Replication with KMS](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html)

```

Perfect! I've successfully implemented the cross-region S3 replication setup with Terragrunt. Let me verify the structure:

Excellent! I've successfully implemented the complete cross-region S3 replication setup with Terragrunt. Here's what was created:

## 📁 Structure Created

```
cloud_repo/
├── terragrunt.hcl                    # Root configuration with shared settings
├── modules/s3/                       # Reusable Terraform module
│   ├── main.tf                       # S3 bucket, KMS, replication config
│   ├── variables.tf                  # Module inputs
│   └── outputs.tf                    # Bucket ARN, KMS ARN outputs
└── dev/
    ├── us-west-2/s3/terragrunt.hcl   # US West bucket with dependency on EU
    └── eu-west-2/s3/terragrunt.hcl   # EU West bucket with dependency on US
```

## 🔑 Key Implementation Details

### How Dependencies Work

In **`cloud_repo/dev/eu-west-2/s3/terragrunt.hcl`**:
```hcl
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
  mock_outputs = { ... }  # Used before dependency exists
}

inputs = {
  replication_destination_bucket_arn = dependency.us_west_2.outputs.bucket_arn
  replication_destination_kms_arn    = dependency.us_west_2.outputs.kms_key_arn
}
```

### The Module Exports These Outputs

From **`cloud_repo/modules/s3/outputs.tf`**:
- `bucket_name` - The S3 bucket name
- `bucket_arn` - Required for replication destination
- `kms_key_arn` - Required for cross-region encryption

## 🚀 Deployment Instructions

Since both regions depend on each other (bi-directional replication), use this bootstrap approach:

### **Option 1: Two-Stage Deployment (Recommended)**

```bash
# Stage 1: Deploy without replication
cd cloud_repo/dev/us-west-2/s3
# Set enable_replication = false temporarily
terragrunt apply

cd ../../../eu-west-2/s3
# Set enable_replication = false temporarily
terragrunt apply

# Stage 2: Enable replication and re-apply
# Set enable_replication = true in both files
cd ../../us-west-2/s3
terragrunt apply

cd ../../../eu-west-2/s3
terragrunt apply
```

### **Option 2: Sequential with Mock Outputs**

```bash
# 1. Deploy us-west-2 (uses mock outputs for eu-west-2)
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

# 2. Deploy eu-west-2 (gets real outputs from us-west-2)
cd ../../../eu-west-2/s3
terragrunt apply

# 3. Re-apply us-west-2 (now gets real outputs from eu-west-2)
cd ../../us-west-2/s3
terragrunt apply
```

## ✨ What You Get

✅ **Bi-directional replication** between us-west-2 and eu-west-2  
✅ **KMS encryption** with region-specific keys  
✅ **Cross-region dependency management** using Terragrunt  
✅ **Separate state files** per region (as per your company's structure)  
✅ **Automatic IAM roles** for replication  
✅ **Versioning enabled** (required for replication)  

The README.md contains complete documentation including troubleshooting tips and customization options. You can adapt this pattern for any other regions or services that need cross-region dependencies!

```plaintext
cloud_repo/
├── terragrunt.hcl                    # Root configuration with shared settings
├── modules/s3/                       # Reusable Terraform module
│   ├── main.tf                       # S3 bucket, KMS, replication config
│   ├── variables.tf                  # Module inputs
│   └── outputs.tf                    # Bucket ARN, KMS ARN outputs
└── dev/
    ├── us-west-2/s3/terragrunt.hcl   # US West bucket with dependency on EU
    └── eu-west-2/s3/terragrunt.hcl   # EU West bucket with dependency on US
```

```plaintext
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
  mock_outputs = { ... }  # Used before dependency exists
}

inputs = {
  replication_destination_bucket_arn = dependency.us_west_2.outputs.bucket_arn
  replication_destination_kms_arn    = dependency.us_west_2.outputs.kms_key_arn
}
```

```shellscript
# Stage 1: Deploy without replication
cd cloud_repo/dev/us-west-2/s3
# Set enable_replication = false temporarily
terragrunt apply

cd ../../../eu-west-2/s3
# Set enable_replication = false temporarily
terragrunt apply

# Stage 2: Enable replication and re-apply
# Set enable_replication = true in both files
cd ../../us-west-2/s3
terragrunt apply

cd ../../../eu-west-2/s3
terragrunt apply
```

```shellscript
# 1. Deploy us-west-2 (uses mock outputs for eu-west-2)
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

# 2. Deploy eu-west-2 (gets real outputs from us-west-2)
cd ../../../eu-west-2/s3
terragrunt apply

# 3. Re-apply us-west-2 (now gets real outputs from eu-west-2)
cd ../../us-west-2/s3
terragrunt apply
```

---

**User**

is there a way instead of defining the destination kms arn to use tags to identify it?

---

**Cursor**

```plaintext
Resource = var.replication_destination_kms_arn
```

Great question! Yes, you can use tags to identify the KMS key instead of passing the ARN directly. However, there are some trade-offs to consider.

Let me show you two approaches:

## Approach 1: Data Source with Tags (Alternative to Dependencies)

You can use a `data` source to look up the KMS key by tags. This would require configuring an additional AWS provider for the destination region.

Let me update the module to support this:

Now let me create an enhanced version that supports tag-based KMS key lookup:

```plaintext
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

```

```plaintext
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_tags" {
  description = "Additional tags to apply specifically to KMS key for identification"
  type        = map(string)
  default     = {}
}

variable "enable_replication" {
  description = "Enable S3 replication to another region"
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination bucket for replication"
  type        = string
  default     = ""
}

# Traditional approach - direct ARN
variable "replication_destination_kms_arn" {
  description = "ARN of the destination KMS key for replication (used when use_kms_tag_lookup is false)"
  type        = string
  default     = ""
}

# Tag-based lookup approach
variable "use_kms_tag_lookup" {
  description = "Use tag-based lookup to find destination KMS key instead of direct ARN"
  type        = bool
  default     = false
}

variable "replication_destination_kms_alias" {
  description = "KMS key alias in destination region (e.g., 'my-bucket-name' for alias/my-bucket-name)"
  type        = string
  default     = ""
}

variable "replication_destination_kms_tags" {
  description = "Tags to identify the destination KMS key (used when use_kms_tag_lookup is true and alias is not provided)"
  type        = map(string)
  default     = {}
}

variable "replication_storage_class" {
  description = "Storage class for replicated objects"
  type        = string
  default     = "STANDARD"
}

variable "destination_region" {
  description = "Destination region for replication (required for tag-based KMS lookup)"
  type        = string
  default     = ""
}

```

```plaintext
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

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.s3.name
}

output "replication_role_arn" {
  description = "ARN of the replication IAM role (if replication is enabled)"
  value       = var.enable_replication ? aws_iam_role.replication[0].arn : null
}

output "resolved_destination_kms_arn" {
  description = "The resolved destination KMS ARN (useful for debugging tag lookups)"
  value       = local.destination_kms_arn
}

```

```plaintext
# Example configuration using TAG-BASED KMS key lookup
# This approach uses KMS key alias instead of Terragrunt dependencies

terraform {
  source = "../../../modules/s3-with-tag-lookup"
}

include "root" {
  path = find_in_parent_folders()
}

# Generate additional provider for destination region
generate "provider_destination" {
  path      = "provider_destination.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  alias  = "destination"
  region = "us-west-2"
  
  default_tags {
    tags = {
      Environment = "dev"
      Region      = "us-west-2"
      ManagedBy   = "Terragrunt"
    }
  }
}
EOF
}

# NO DEPENDENCY BLOCK NEEDED! 
# Instead, we use KMS alias or tags to identify the destination key

inputs = {
  bucket_name = "my-company-eu-west-2-bucket-dev"
  
  # KMS key tags for identification
  kms_key_tags = {
    ReplicationKey = "true"
    BucketRegion   = "eu-west-2"
  }
  
  # Enable replication with tag-based KMS lookup
  enable_replication     = true
  use_kms_tag_lookup    = true
  destination_region    = "us-west-2"
  
  # OPTION 1: Use KMS alias (recommended - simpler and faster)
  replication_destination_kms_alias = "my-company-us-west-2-bucket-dev"
  
  # OPTION 2: Use tags to find KMS key (more flexible but slower)
  # Uncomment below and remove alias above to use tags instead
  # replication_destination_kms_tags = {
  #   ReplicationKey = "true"
  #   BucketRegion   = "us-west-2"
  # }
  
  # Still need the destination bucket ARN
  # You can hardcode this or use dependency for just the bucket
  replication_destination_bucket_arn = "arn:aws:s3:::my-company-us-west-2-bucket-dev"
  replication_storage_class          = "STANDARD"
  
  kms_deletion_window = 30
  
  tags = {
    Environment = "dev"
    Region      = "eu-west-2"
    ManagedBy   = "Terragrunt"
    Service     = "s3-replication"
  }
}

```

```plaintext
# Example configuration using TAG-BASED KMS key lookup
# This approach uses KMS key alias instead of Terragrunt dependencies

terraform {
  source = "../../../modules/s3-with-tag-lookup"
}

include "root" {
  path = find_in_parent_folders()
}

# Generate additional provider for destination region
generate "provider_destination" {
  path      = "provider_destination.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  alias  = "destination"
  region = "eu-west-2"
  
  default_tags {
    tags = {
      Environment = "dev"
      Region      = "eu-west-2"
      ManagedBy   = "Terragrunt"
    }
  }
}
EOF
}

# NO DEPENDENCY BLOCK NEEDED! 
# Instead, we use KMS alias or tags to identify the destination key

inputs = {
  bucket_name = "my-company-us-west-2-bucket-dev"
  
  # KMS key tags for identification
  kms_key_tags = {
    ReplicationKey = "true"
    BucketRegion   = "us-west-2"
  }
  
  # Enable replication with tag-based KMS lookup
  enable_replication     = true
  use_kms_tag_lookup    = true
  destination_region    = "eu-west-2"
  
  # OPTION 1: Use KMS alias (recommended - simpler and faster)
  replication_destination_kms_alias = "my-company-eu-west-2-bucket-dev"
  
  # OPTION 2: Use tags to find KMS key (more flexible but slower)
  # Uncomment below and remove alias above to use tags instead
  # replication_destination_kms_tags = {
  #   ReplicationKey = "true"
  #   BucketRegion   = "eu-west-2"
  # }
  
  # Still need the destination bucket ARN
  # You can hardcode this or use dependency for just the bucket
  replication_destination_bucket_arn = "arn:aws:s3:::my-company-eu-west-2-bucket-dev"
  replication_storage_class          = "STANDARD"
  
  kms_deletion_window = 30
  
  tags = {
    Environment = "dev"
    Region      = "us-west-2"
    ManagedBy   = "Terragrunt"
    Service     = "s3-replication"
  }
}

```

```markdown
# Tag-Based KMS Key Lookup for S3 Replication

This document explains the alternative approach to finding KMS keys using tags or aliases instead of Terragrunt dependencies.

## Overview

Instead of using Terragrunt's `dependency` blocks to pass KMS ARNs between regions, you can use AWS data sources to look up KMS keys by:
1. **KMS Alias** (recommended - simpler and faster)
2. **Tags** (more flexible but requires more configuration)

## Comparison: Dependencies vs Tag Lookup

### Approach 1: Terragrunt Dependencies (Original)

**Pros:**
- ✅ Explicit dependencies ensure correct apply order
- ✅ Type-safe - Terraform knows the exact ARN
- ✅ Faster - no API calls to lookup resources
- ✅ Clear relationship between resources

**Cons:**
- ❌ Requires careful deployment order for circular dependencies
- ❌ Needs mock outputs for initial deployment
- ❌ Tightly coupled between regions

### Approach 2: Tag/Alias Lookup (Alternative)

**Pros:**
- ✅ No circular dependencies - can deploy independently
- ✅ Looser coupling between regions
- ✅ Can use naming conventions (aliases) instead of passing ARNs
- ✅ No mock outputs needed

**Cons:**
- ❌ Requires additional AWS provider for destination region
- ❌ API calls during plan/apply (slightly slower)
- ❌ Potential for runtime errors if key not found
- ❌ Still need to know bucket ARN (or hardcode bucket naming convention)

## Implementation

### Module Structure

The new module `s3-with-tag-lookup` includes:

1. **Provider Alias**: Configures AWS provider for destination region
2. **Data Sources**: Looks up KMS keys by alias or tags
3. **Local Values**: Resolves which KMS ARN to use based on lookup method

### Usage Example

#### Option 1: Using KMS Alias (Recommended)

```hcl
# terragrunt.hcl
terraform {
  source = "../../../modules/s3-with-tag-lookup"
}

# Generate destination region provider
generate "provider_destination" {
  path      = "provider_destination.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  alias  = "destination"
  region = "us-west-2"
}
EOF
}

inputs = {
  bucket_name = "my-bucket-eu-west-2"
  
  # Enable tag-based lookup
  enable_replication     = true
  use_kms_tag_lookup    = true
  
  # Use alias to find KMS key
  replication_destination_kms_alias = "my-bucket-us-west-2"
  
  # Bucket ARN (can hardcode if following naming convention)
  replication_destination_bucket_arn = "arn:aws:s3:::my-bucket-us-west-2"
  
  kms_key_tags = {
    ReplicationKey = "true"
    BucketRegion   = "eu-west-2"
  }
}
```

#### Option 2: Using Tags

```hcl
inputs = {
  bucket_name = "my-bucket-eu-west-2"
  
  # Enable tag-based lookup
  enable_replication     = true
  use_kms_tag_lookup    = true
  
  # Use tags to find KMS key
  replication_destination_kms_tags = {
    ReplicationKey = "true"
    BucketRegion   = "us-west-2"
    Environment    = "dev"
  }
  
  replication_destination_bucket_arn = "arn:aws:s3:::my-bucket-us-west-2"
  
  kms_key_tags = {
    ReplicationKey = "true"
    BucketRegion   = "eu-west-2"
  }
}
```

## How It Works

### 1. KMS Key Creation with Tags

```hcl
resource "aws_kms_key" "s3" {
  description = "KMS key for S3 bucket encryption - ${var.bucket_name}"
  
  tags = merge(
    var.tags,
    var.kms_key_tags,  # Add specific tags for identification
    {
      Name = "${var.bucket_name}-kms-key"
    }
  )
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.s3.key_id
}
```

### 2. Data Source Lookup (Alias Method)

```hcl
data "aws_kms_key" "destination" {
  count    = var.use_kms_tag_lookup ? 1 : 0
  provider = aws.destination
  
  key_id = "alias/${var.replication_destination_kms_alias}"
}
```

### 3. Data Source Lookup (Tag Method)

```hcl
# List all KMS keys
data "aws_kms_keys" "destination" {
  count    = var.use_kms_tag_lookup ? 1 : 0
  provider = aws.destination
}

# Get details for each key
data "aws_kms_key" "destination_filtered" {
  count    = length(data.aws_kms_keys.destination[0].keys)
  provider = aws.destination
  key_id   = data.aws_kms_keys.destination[0].keys[count.index]
}

# Filter by tags in locals
locals {
  matching_kms_arn = [
    for k in data.aws_kms_key.destination_filtered : k.arn 
    if alltrue([
      for tag_key, tag_value in var.replication_destination_kms_tags :
      lookup(k.tags, tag_key, "") == tag_value
    ])
  ][0]
}
```

### 4. Use in IAM Policy

```hcl
locals {
  destination_kms_arn = var.use_kms_tag_lookup ? 
    data.aws_kms_key.destination[0].arn : 
    var.replication_destination_kms_arn
}

resource "aws_iam_role_policy" "replication" {
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt"]
        Resource = local.destination_kms_arn  # Uses looked-up ARN
      }
    ]
  })
}
```

## Deployment

### Initial Setup

```bash
# 1. Deploy us-west-2 first
cd cloud_repo/dev/us-west-2/s3
terragrunt apply

# 2. Deploy eu-west-2 (will lookup us-west-2 KMS key)
cd ../../../eu-west-2/s3
terragrunt apply

# 3. Re-apply us-west-2 (will lookup eu-west-2 KMS key)
cd ../../us-west-2/s3
terragrunt apply
```

No circular dependency issues! Each can lookup the other's KMS key independently.

## Best Practices

### 1. Use Consistent Naming Convention

Establish a pattern for KMS aliases:
```
alias/${environment}-${service}-${region}
# Examples:
# alias/dev-s3-us-west-2
# alias/prod-s3-eu-west-2
```

### 2. Use Meaningful Tags

```hcl
kms_key_tags = {
  Service        = "s3-replication"
  Environment    = "dev"
  BucketRegion   = "us-west-2"
  ReplicationKey = "true"
}
```

### 3. Prefer Alias over Tags

Alias lookup is:
- Faster (single API call vs listing all keys)
- More reliable (aliases are unique)
- Simpler to implement

### 4. Handle Missing Keys Gracefully

Add validation:
```hcl
resource "null_resource" "validate_kms_lookup" {
  count = var.enable_replication && var.use_kms_tag_lookup ? 1 : 0
  
  provisioner "local-exec" {
    command = "test -n '${local.destination_kms_arn}' || (echo 'ERROR: Could not find destination KMS key' && exit 1)"
  }
}
```

## Hybrid Approach

You can also use a hybrid approach - use dependencies for bucket ARN but tag lookup for KMS:

```hcl
# Still use dependency for bucket
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
}

inputs = {
  # Use dependency for bucket
  replication_destination_bucket_arn = dependency.us_west_2.outputs.bucket_arn
  
  # Use tag lookup for KMS
  use_kms_tag_lookup = true
  replication_destination_kms_alias = "my-bucket-us-west-2"
}
```

## Troubleshooting

### KMS Key Not Found

```bash
# Verify the KMS key exists with correct alias
aws kms describe-key --key-id alias/my-bucket-name --region us-west-2

# List all aliases
aws kms list-aliases --region us-west-2

# Check key tags
aws kms list-resource-tags --key-id <key-id> --region us-west-2
```

### Wrong Region

Make sure the destination provider is configured correctly:
```hcl
generate "provider_destination" {
  contents = <<EOF
provider "aws" {
  alias  = "destination"
  region = "us-west-2"  # Must match actual destination
}
EOF
}
```

### Performance Issues

Tag-based filtering requires listing all KMS keys. For accounts with many keys:
- Prefer alias lookup
- Or continue using Terragrunt dependencies

## When to Use Each Approach

### Use Terragrunt Dependencies When:
- You want strong type safety and explicit dependencies
- Performance is critical (no data source API calls)
- You're managing all infrastructure with Terragrunt
- You prefer compile-time validation

### Use Tag/Alias Lookup When:
- You want loose coupling between regions
- Circular dependencies are problematic
- You follow consistent naming conventions
- You deploy regions independently
- Some resources are managed outside Terragrunt

## Recommendation

For your specific use case with S3 replication:

**Best Option:** Use **KMS Alias lookup** (Option 1 in the examples)

**Why:**
1. No circular dependency issues
2. Simple and predictable - just use bucket name as alias
3. Fast - single API call per region
4. Still maintains separation of state files
5. Easier to reason about than tag filtering

**Naming Convention:**
```
Bucket: my-company-${region}-bucket-${environment}
KMS Alias: alias/my-company-${region}-bucket-${environment}
```

Then in your terragrunt.hcl:
```hcl
locals {
  region_name = "eu-west-2"
  dest_region = "us-west-2"
}

inputs = {
  bucket_name = "my-company-${local.region_name}-bucket-dev"
  replication_destination_kms_alias = "my-company-${local.dest_region}-bucket-dev"
}
```

This gives you the independence you want while maintaining clarity!

```

Perfect! I've created an alternative module that supports tag-based KMS key lookup. Let me show you the structure:

Excellent! Now you have **two approaches** for handling cross-region KMS references:

## 📦 What I Created

### **Approach 1: Terragrunt Dependencies** (Original - in `modules/s3/`)
- Uses `dependency` blocks to pass KMS ARNs between regions
- Explicit dependencies, type-safe, fast
- Requires careful ordering for circular dependencies

### **Approach 2: Tag/Alias Lookup** (New - in `modules/s3-with-tag-lookup/`)
- Uses AWS data sources to find KMS keys by alias or tags
- No dependency blocks needed
- Independent deployment, looser coupling

## 🔑 Key Differences

### In the IAM Policy (Line 132 you highlighted):

**Original approach:**
```hcl
Resource = var.replication_destination_kms_arn  # Passed via Terragrunt dependency
```

**Tag lookup approach:**
```hcl
Resource = local.destination_kms_arn  # Looked up via data source
```

Where `local.destination_kms_arn` is resolved using:
```hcl
# Option 1: By alias (recommended)
data "aws_kms_key" "destination" {
  provider = aws.destination
  key_id   = "alias/${var.replication_destination_kms_alias}"
}

# Option 2: By tags (more complex)
# Filters all KMS keys by matching tags
```

## 🚀 Usage Example (Tag Lookup Method)

Instead of:
```hcl
# OLD: With dependency block
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
}

inputs = {
  replication_destination_kms_arn = dependency.us_west_2.outputs.kms_key_arn
}
```

You can now do:
```hcl
# NEW: With KMS alias lookup
generate "provider_destination" {
  path = "provider_destination.tf"
  contents = <<EOF
provider "aws" {
  alias  = "destination"
  region = "us-west-2"
}
EOF
}

inputs = {
  use_kms_tag_lookup = true
  replication_destination_kms_alias = "my-company-us-west-2-bucket-dev"
  # No dependency block needed!
}
```

## 📊 Comparison Table

| Feature | Dependencies | Tag/Alias Lookup |
|---------|-------------|------------------|
| **KMS ARN Resolution** | Via Terragrunt outputs | Via AWS data source |
| **Circular Dependencies** | ❌ Requires bootstrap | ✅ No issues |
| **Performance** | ✅ Fast (no API calls) | ⚠️ Slightly slower |
| **Coupling** | Strong | Loose |
| **Error Detection** | Compile-time | Runtime |
| **Setup Complexity** | Simple | Need provider alias |

## 💡 My Recommendation

Use **KMS Alias Lookup** (the new approach) with this pattern:

```hcl
# Establish naming convention
bucket_name = "my-company-${region}-bucket-${env}"
kms_alias   = "alias/my-company-${region}-bucket-${env}"

# In eu-west-2 terragrunt.hcl
inputs = {
  bucket_name = "my-company-eu-west-2-bucket-dev"
  use_kms_tag_lookup = true
  replication_destination_kms_alias = "my-company-us-west-2-bucket-dev"
}
```

**Benefits:**
- ✅ No circular dependency issues
- ✅ Deploy regions independently  
- ✅ Simple and predictable
- ✅ Maintains separate state files (as your company requires)
- ✅ Just one extra line per region to configure destination provider

Check out `TAG_LOOKUP_APPROACH.md` for complete documentation with examples and best practices!

```plaintext
Resource = var.replication_destination_kms_arn  # Passed via Terragrunt dependency
```

```plaintext
Resource = local.destination_kms_arn  # Looked up via data source
```

```plaintext
# Option 1: By alias (recommended)
data "aws_kms_key" "destination" {
  provider = aws.destination
  key_id   = "alias/${var.replication_destination_kms_alias}"
}

# Option 2: By tags (more complex)
# Filters all KMS keys by matching tags
```

```plaintext
# OLD: With dependency block
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
}

inputs = {
  replication_destination_kms_arn = dependency.us_west_2.outputs.kms_key_arn
}
```

```plaintext
# NEW: With KMS alias lookup
generate "provider_destination" {
  path = "provider_destination.tf"
  contents = <<EOF
provider "aws" {
  alias  = "destination"
  region = "us-west-2"
}
EOF
}

inputs = {
  use_kms_tag_lookup = true
  replication_destination_kms_alias = "my-company-us-west-2-bucket-dev"
  # No dependency block needed!
}
```

```plaintext
# Establish naming convention
bucket_name = "my-company-${region}-bucket-${env}"
kms_alias   = "alias/my-company-${region}-bucket-${env}"

# In eu-west-2 terragrunt.hcl
inputs = {
  bucket_name = "my-company-eu-west-2-bucket-dev"
  use_kms_tag_lookup = true
  replication_destination_kms_alias = "my-company-us-west-2-bucket-dev"
}
```

