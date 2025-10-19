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

