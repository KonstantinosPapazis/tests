# Terragrunt Configuration Examples

This directory contains production-ready Terragrunt configurations for deploying Aurora PostgreSQL using the Terragrunt workflow.

## Directory Structure

```
terragrunt-examples/
├── README.md                           # This file
├── production-serverless/
│   └── terragrunt.hcl                 # Serverless v2 configuration
├── production-provisioned/
│   └── terragrunt.hcl                 # Provisioned cluster configuration
└── common/
    └── terragrunt.hcl.example         # Shared configuration (optional)
```

## Prerequisites

- Terragrunt >= 0.48.0
- Terraform >= 1.5.0
- AWS CLI configured
- S3 bucket for remote state
- DynamoDB table for state locking

## Setup Remote State Infrastructure

Before using these configurations, create the required infrastructure:

```bash
# Create S3 bucket for state
aws s3 mb s3://my-company-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-company-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-company-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Quick Start - Serverless v2

### 1. Navigate to Directory

```bash
cd terragrunt-examples/production-serverless
```

### 2. Update Configuration

Edit `terragrunt.hcl` and update:

```hcl
# Remote state bucket
bucket = "YOUR-STATE-BUCKET"

# VPC ID
vpc_id = "vpc-YOUR-VPC-ID"

# Email addresses for alarms
alarm_email_addresses = ["your-team@example.com"]

# Cluster identifier
cluster_identifier = "your-cluster-name"
```

### 3. Deploy

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy (when needed)
terragrunt destroy
```

## Quick Start - Provisioned

Same steps as serverless, but use the `production-provisioned` directory:

```bash
cd terragrunt-examples/production-provisioned
# Edit terragrunt.hcl
terragrunt plan
terragrunt apply
```

## Key Configuration Sections

### 1. Remote State

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "my-company-terraform-state"
    key            = "aurora/production-serverless/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### 2. Provider Generation

Terragrunt auto-generates the provider configuration:

```hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = var.aws_region
  # ... default tags
}
EOF
}
```

### 3. Module Source

Point to your Terraform modules:

```hcl
terraform {
  # Local (development)
  source = "../../environments/production-serverless"
  
  # Git (production)
  # source = "git::https://github.com/org/repo.git//path?ref=v1.0.0"
}
```

### 4. Inputs

All module variables passed via `inputs` block:

```hcl
inputs = {
  cluster_identifier      = "prod-aurora"
  serverless_min_capacity = 0.5
  serverless_max_capacity = 16
  # ... all other variables
}
```

## Terragrunt Features Used

### Auto-generated Files

Terragrunt generates these files automatically:
- `backend.tf` - Remote state configuration
- `provider.tf` - AWS provider configuration
- `variables.tf` - Variable definitions

### Hooks

Pre/post execution hooks for validation:

```hcl
terraform {
  before_hook "validate" {
    commands = ["apply", "plan"]
    execute  = ["bash", "-c", "echo 'Validating...'"]
  }
}
```

### Dependencies (Optional)

If your Aurora depends on other infrastructure:

```hcl
dependency "vpc" {
  config_path = "../vpc"
  
  mock_outputs = {
    vpc_id = "vpc-mock"
  }
}

inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id
}
```

## Environment-Specific Configurations

### Development

```hcl
inputs = {
  cluster_identifier              = "dev-aurora"
  instance_count                  = 1
  serverless_min_capacity         = 0.5
  serverless_max_capacity         = 4
  backup_retention_period         = 7
  deletion_protection             = false
  enable_performance_insights     = false
  create_cloudwatch_alarms        = false
}
```

### Staging

```hcl
inputs = {
  cluster_identifier              = "staging-aurora"
  instance_count                  = 2
  serverless_min_capacity         = 0.5
  serverless_max_capacity         = 8
  backup_retention_period         = 14
  deletion_protection             = true
  enable_performance_insights     = true
}
```

### Production

Use the provided configurations with:
```hcl
inputs = {
  cluster_identifier              = "prod-aurora"
  instance_count                  = 2
  serverless_min_capacity         = 1
  serverless_max_capacity         = 32
  backup_retention_period         = 30
  deletion_protection             = true
  enable_performance_insights     = true
  performance_insights_retention_period = 731
}
```

## Multi-Region Setup

For multi-region deployments:

```
terragrunt-examples/
├── us-east-1/
│   └── production-serverless/
│       └── terragrunt.hcl
├── eu-west-1/
│   └── production-serverless/
│       └── terragrunt.hcl
└── common.hcl                  # Shared configuration
```

Example `common.hcl`:

```hcl
locals {
  project_name = "my-app"
  cost_center  = "engineering"
  
  common_tags = {
    Project    = local.project_name
    ManagedBy  = "terragrunt"
  }
}
```

Reference in region-specific configs:

```hcl
include "root" {
  path = find_in_parent_folders("common.hcl")
}

inputs = merge(
  local.common_tags,
  {
    cluster_identifier = "prod-aurora-${local.region}"
    # ... other inputs
  }
)
```

## Best Practices

### 1. Use Git Tags for Module Versions

```hcl
terraform {
  source = "git::https://github.com/org/repo.git//aurora_postgres_rds/environments/production-serverless?ref=v1.2.3"
}
```

### 2. DRY (Don't Repeat Yourself)

Use `include` blocks and `locals`:

```hcl
include "common" {
  path = find_in_parent_folders("common.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  region = "us-east-1"
}
```

### 3. Separate State Per Environment

```
bucket/
├── aurora/
│   ├── dev/terraform.tfstate
│   ├── staging/terraform.tfstate
│   └── production/terraform.tfstate
```

### 4. Use Mock Outputs for Dependencies

```hcl
dependency "vpc" {
  config_path = "../vpc"
  
  mock_outputs = {
    vpc_id = "vpc-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

### 5. Validate Before Apply

```bash
# Validate configuration
terragrunt validate

# Plan and save
terragrunt plan -out=tfplan

# Review and apply
terragrunt apply tfplan
```

## Useful Commands

```bash
# Initialize without running
terragrunt init

# Plan changes
terragrunt plan

# Apply with auto-approve (CI/CD)
terragrunt apply -auto-approve

# Show current state
terragrunt show

# List outputs
terragrunt output

# Get specific output
terragrunt output cluster_endpoint

# Format code
terragrunt hclfmt

# Validate configuration
terragrunt validate

# Run on all modules (if using multiple)
terragrunt run-all plan
terragrunt run-all apply
```

## Troubleshooting

### Issue: State Lock Error

```bash
# Force unlock (use with caution!)
terragrunt force-unlock LOCK-ID
```

### Issue: Module Not Found

Check the `source` path in `terragrunt.hcl`:

```hcl
terraform {
  # Ensure path is correct relative to terragrunt.hcl
  source = "../../environments/production-serverless"
}
```

### Issue: AWS Credentials

```bash
# Verify credentials
aws sts get-caller-identity

# Use specific profile
export AWS_PROFILE=my-profile
terragrunt apply
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Aurora

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      
      - name: Setup Terragrunt
        run: |
          wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.48.0/terragrunt_linux_amd64
          chmod +x terragrunt_linux_amd64
          sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Terragrunt Plan
        working-directory: terragrunt-examples/production-serverless
        run: terragrunt plan
      
      - name: Terragrunt Apply
        if: github.ref == 'refs/heads/main'
        working-directory: terragrunt-examples/production-serverless
        run: terragrunt apply -auto-approve
```

## Migration from Terraform to Terragrunt

If you're currently using Terraform directly:

1. **Copy your tfvars values to terragrunt.hcl inputs**
2. **Update module source paths**
3. **Configure remote state**
4. **Run terragrunt init**
5. **Import existing state** (if needed):

```bash
terragrunt import 'module.aurora_cluster.aws_rds_cluster.main' cluster-id
```

## Support

For issues with:
- **Terragrunt**: https://github.com/gruntwork-io/terragrunt
- **Aurora modules**: See main README.md
- **AWS Aurora**: AWS documentation

## Additional Resources

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)

