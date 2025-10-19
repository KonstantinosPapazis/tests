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

