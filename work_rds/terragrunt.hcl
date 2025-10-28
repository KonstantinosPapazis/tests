terraform {
  source = "git://modules/rds?ref=0.0.12"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}


inputs = {
  serverless_min_capacity = 0.5
  serverless_max_capacity = 4
  engine_version = "13.20"
  allowed_security_groups = [
    # "sg-0123456789abcdef0",  # Application security group
    # "sg-abcdef0123456789",   # Bastion security group
  ]
  parameter_group =[
    max_connections =20
  ]
  kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

  
  tags = {
    Environment = "dev"
    Region      = "us-west-2"
    ManagedBy   = "Terragrunt"
    Service     = "s3-replication"
  }
}

