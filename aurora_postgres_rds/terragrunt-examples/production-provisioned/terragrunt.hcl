##############################################
# Terragrunt Configuration for Aurora PostgreSQL Provisioned
# Production-ready configuration with all inputs
##############################################

# Configure Terragrunt to use remote state
remote_state {
  backend = "s3"
  
  config = {
    bucket         = "my-company-terraform-state"        # Change to your state bucket
    key            = "aurora/production-provisioned/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"              # Change to your lock table
    
    s3_bucket_tags = {
      Name        = "Terraform State"
      Environment = "production"
      ManagedBy   = "terragrunt"
    }
    
    dynamodb_table_tags = {
      Name        = "Terraform State Lock"
      Environment = "production"
      ManagedBy   = "terragrunt"
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
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment   = "production"
      ManagedBy     = "terragrunt"
      Project       = var.project_name
      CostCenter    = var.cost_center
      Owner         = "platform-team"
      Terraform     = "true"
      Configuration = "aurora-provisioned"
    }
  }
}
EOF
}

# Generate variables file
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "cost_center" {
  description = "Cost center"
  type        = string
}
EOF
}

##############################################
# Terraform Source
##############################################

terraform {
  source = "../../environments/production-provisioned"
}

##############################################
# Inputs - All module variables
##############################################

inputs = {
  
  ##############################################
  # General Configuration
  ##############################################
  
  aws_region         = "us-east-1"
  project_name       = "my-application"
  cost_center        = "engineering"
  cluster_identifier = "prod-aurora-postgres"
  
  # PostgreSQL version
  # Options: 16.1, 15.4, 15.5, 14.9, 14.10, 13.12, 13.13
  engine_version = "16.1"
  
  database_name   = "myapp_prod"
  master_username = "postgres"
  
  # Security: Let RDS manage password in Secrets Manager (RECOMMENDED)
  manage_master_password = true
  
  ##############################################
  # Instance Configuration
  ##############################################
  
  # Instance class - Choose based on workload
  # 
  # Graviton (r6g/r7g) - 20% cheaper, recommended:
  # - db.r6g.large     → 2 vCPU,  16 GB RAM  (~$190/month each)
  # - db.r6g.xlarge    → 4 vCPU,  32 GB RAM  (~$380/month each)
  # - db.r6g.2xlarge   → 8 vCPU,  64 GB RAM  (~$760/month each)
  # - db.r6g.4xlarge   → 16 vCPU, 128 GB RAM (~$1,520/month each)
  # - db.r7g.large     → 2 vCPU,  16 GB RAM  (~$210/month each) - Latest gen
  # - db.r7g.xlarge    → 4 vCPU,  32 GB RAM  (~$420/month each)
  #
  # Intel/AMD (r5/r6i):
  # - db.r5.large      → 2 vCPU,  16 GB RAM
  # - db.r5.xlarge     → 4 vCPU,  32 GB RAM
  #
  # Burstable (t4g) - For dev/test only:
  # - db.t4g.medium    → 2 vCPU,  4 GB RAM   (~$65/month each)
  instance_class = "db.r6g.large"
  
  # Number of instances (HIGH AVAILABILITY)
  # Minimum 2 for production (1 writer + 1 reader in different AZs)
  # Can go higher (e.g., 3) for more read capacity
  instance_count = 2
  
  # Availability Zones - Leave empty for automatic selection
  # Or specify: ["us-east-1a", "us-east-1b", "us-east-1c"]
  availability_zones = []
  
  ##############################################
  # Network Configuration
  ##############################################
  
  # Use existing VPC (RECOMMENDED for production)
  create_vpc = false
  vpc_id     = "vpc-0123456789abcdef0"  # CHANGE THIS to your VPC ID
  
  # Access Control - CIDR blocks allowed to connect
  allowed_cidr_blocks = [
    "10.0.0.0/16",  # VPC CIDR
  ]
  
  # Access Control - Security Groups (PREFERRED)
  allowed_security_groups = [
    # "sg-0123456789abcdef0",  # Application security group
  ]
  
  enable_nat_gateway   = true
  enable_vpc_endpoints = true
  
  ##############################################
  # Backup and Maintenance Configuration
  ##############################################
  
  backup_retention_period      = 30
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  skip_final_snapshot          = false
  
  # Backtrack (Point-in-time rewind without restore)
  # 0 to disable, max 259200 seconds (72 hours)
  # Note: Not available for all engine versions
  backtrack_window = 0
  
  ##############################################
  # Encryption Configuration
  ##############################################
  
  storage_encrypted = true
  create_kms_key    = true
  
  ##############################################
  # Parameter Group Configuration
  ##############################################
  
  parameter_group_family     = "aurora-postgresql16"
  log_statement              = "ddl"
  log_min_duration_statement = "1000"
  log_connections            = true
  log_disconnections         = true
  shared_preload_libraries   = "pg_stat_statements,pg_hint_plan"
  work_mem                   = "16384"
  maintenance_work_mem       = "2097152"
  force_ssl                  = true
  
  ##############################################
  # IAM and Authentication
  ##############################################
  
  iam_database_authentication_enabled = true
  
  ##############################################
  # Monitoring Configuration
  ##############################################
  
  enable_enhanced_monitoring            = true
  monitoring_interval                   = 60
  enable_performance_insights           = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  
  ##############################################
  # Auto Scaling Configuration
  ##############################################
  
  # Enable read replica auto-scaling
  enable_autoscaling = true
  
  # Minimum number of read replicas
  # Set to instance_count - 1 (e.g., if instance_count=2, min=1)
  autoscaling_min_capacity = 1
  
  # Maximum number of read replicas
  # Scale based on your read traffic patterns
  autoscaling_max_capacity = 5
  
  # Target CPU utilization for scaling (%)
  # Scale out when CPU > this value
  # Scale in when CPU < (this value - 30%)
  autoscaling_target_cpu = 70
  
  # Target connections for scaling
  # Additional metric for scaling decisions
  autoscaling_target_connections = 700
  
  ##############################################
  # CloudWatch Alarms Configuration
  ##############################################
  
  create_cloudwatch_alarms = true
  create_sns_topic         = true
  
  alarm_email_addresses = [
    "ops-team@example.com",
    "dba-team@example.com",
  ]
  
  ##############################################
  # Advanced Configuration
  ##############################################
  
  deletion_protection        = true
  apply_immediately          = false
  auto_minor_version_upgrade = true
  
  ##############################################
  # Additional Tags
  ##############################################
  
  tags = {
    Application      = "MyApp"
    Team             = "Platform"
    Environment      = "production"
    Compliance       = "SOC2"
    DataClass        = "sensitive"
    BackupRequired   = "true"
    DisasterRecovery = "true"
    InstanceType     = "provisioned"
    ReservedInstance = "planned"  # Track RI planning
  }
}

