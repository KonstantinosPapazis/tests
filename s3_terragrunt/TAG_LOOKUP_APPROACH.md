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

