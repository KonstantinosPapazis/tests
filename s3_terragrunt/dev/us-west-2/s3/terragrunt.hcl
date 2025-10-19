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

