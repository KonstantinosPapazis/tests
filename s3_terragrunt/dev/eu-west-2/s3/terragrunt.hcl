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

