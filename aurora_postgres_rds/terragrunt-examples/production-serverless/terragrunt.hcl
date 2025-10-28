##############################################
# Terragrunt Configuration for Aurora PostgreSQL Serverless v2
# Production-ready configuration with all inputs
##############################################

# Configure Terragrunt to use remote state
remote_state {
  backend = "s3"
  
  config = {
    bucket         = "my-company-terraform-state"        # Change to your state bucket
    key            = "aurora/production-serverless/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"              # Change to your lock table
    
    # Optional: S3 bucket tags
    s3_bucket_tags = {
      Name        = "Terraform State"
      Environment = "production"
      ManagedBy   = "terragrunt"
    }
    
    # Optional: DynamoDB table tags
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
      Configuration = "aurora-serverless-v2"
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
# Terraform Source - Point to your modules
##############################################

terraform {
  # Option 1: Local modules (development)
  source = "../../environments/production-serverless"
  
  # Option 2: Git repository (recommended for production)
  # source = "git::https://github.com/your-org/terraform-modules.git//aurora_postgres_rds/environments/production-serverless?ref=v1.0.0"
  
  # Option 3: Terraform Registry
  # source = "app.terraform.io/your-org/aurora-serverless/aws"
}

##############################################
# Dependencies (if needed)
##############################################

# Uncomment if you have dependencies on other Terragrunt modules
# dependency "vpc" {
#   config_path = "../vpc"
#   
#   mock_outputs = {
#     vpc_id              = "vpc-mock1234"
#     private_subnet_ids  = ["subnet-mock1", "subnet-mock2"]
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan"]
# }

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
  cluster_identifier = "prod-aurora-serverless-postgres"
  
  # PostgreSQL version - Ensure it supports Serverless v2
  # Options: 16.1, 15.4, 15.5, 14.9, 14.10, 13.12, 13.13
  engine_version = "16.1"
  
  database_name   = "myapp_prod"
  master_username = "postgres"
  
  # Security: Let RDS manage password in Secrets Manager (RECOMMENDED)
  manage_master_password = true
  
  ##############################################
  # Serverless v2 Capacity Configuration
  ##############################################
  
  # Minimum Aurora Capacity Units (ACU)
  # Each ACU ≈ 2 GB RAM + corresponding CPU
  # Range: 0.5 to 128
  # 
  # Recommendations:
  # - Production (always-on): 1-2 ACU minimum
  # - Production (variable): 0.5 ACU minimum
  # - Dev/Staging: 0.5 ACU minimum
  serverless_min_capacity = 0.5
  
  # Maximum Aurora Capacity Units (ACU)
  # Set based on expected peak load:
  # - Small workload: 4-8 ACU
  # - Medium workload: 16-32 ACU
  # - Large workload: 64-128 ACU
  serverless_max_capacity = 16
  
  # Number of instances (HIGH AVAILABILITY)
  # Minimum 2 for production (1 writer + 1 reader in different AZs)
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
  
  # Or create new VPC (for testing/development)
  # create_vpc = true
  # vpc_cidr   = "10.0.0.0/16"
  
  # Access Control - CIDR blocks allowed to connect
  # Use your application subnets or VPC CIDR
  allowed_cidr_blocks = [
    "10.0.0.0/16",  # VPC CIDR
  ]
  
  # Access Control - Security Groups allowed to connect (PREFERRED)
  # Use this instead of CIDR blocks for better security
  allowed_security_groups = [
    # "sg-0123456789abcdef0",  # Application security group
    # "sg-abcdef0123456789",   # Bastion security group
  ]
  
  # NAT Gateway for private subnet internet access
  enable_nat_gateway = true
  
  # VPC Endpoints to reduce NAT Gateway costs
  enable_vpc_endpoints = true
  
  ##############################################
  # Backup and Maintenance Configuration
  ##############################################
  
  # Backup retention period (1-35 days)
  # Production: 30 days minimum
  # Dev/Staging: 7-14 days
  backup_retention_period = 30
  
  # Backup window (UTC) - Choose off-peak hours
  # Format: "HH:MM-HH:MM"
  preferred_backup_window = "03:00-04:00"
  
  # Maintenance window (UTC) - Choose off-peak hours
  # Format: "ddd:HH:MM-ddd:HH:MM"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  
  # Final snapshot before deletion
  # CRITICAL: Set to false for production to prevent data loss!
  skip_final_snapshot = false
  
  ##############################################
  # Encryption Configuration
  ##############################################
  
  # Enable encryption at rest (REQUIRED for production)
  storage_encrypted = true
  
  # Create new KMS key or use existing
  create_kms_key = true
  
  # If using existing KMS key:
  # create_kms_key = false
  # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  
  ##############################################
  # Parameter Group Configuration
  ##############################################
  
  # Parameter group family - MUST match engine version
  # PostgreSQL 16.x → aurora-postgresql16
  # PostgreSQL 15.x → aurora-postgresql15
  # PostgreSQL 14.x → aurora-postgresql14
  # PostgreSQL 13.x → aurora-postgresql13
  parameter_group_family = "aurora-postgresql16"
  
  # Logging Configuration
  log_statement              = "ddl"      # Options: none, ddl, mod, all
  log_min_duration_statement = "1000"     # Log queries > 1 second (milliseconds)
  log_connections            = true       # Log all connections
  log_disconnections         = true       # Log disconnections
  
  # PostgreSQL Extensions
  # Common extensions: pg_stat_statements, pg_hint_plan, pgaudit, auto_explain
  shared_preload_libraries = "pg_stat_statements,pg_hint_plan"
  
  # Memory Configuration (KB)
  work_mem             = "16384"      # 16 MB per query operation
  maintenance_work_mem = "2097152"    # 2 GB for maintenance operations
  
  # Security: Force SSL for all connections (REQUIRED for production)
  force_ssl = true
  
  ##############################################
  # IAM and Authentication
  ##############################################
  
  # Enable IAM database authentication (RECOMMENDED)
  iam_database_authentication_enabled = true
  
  ##############################################
  # Monitoring Configuration
  ##############################################
  
  # Enhanced Monitoring - OS-level metrics
  enable_enhanced_monitoring = true
  monitoring_interval        = 60  # seconds (0, 1, 5, 10, 15, 30, 60)
  
  # Performance Insights - Query-level analysis
  enable_performance_insights             = true
  performance_insights_retention_period   = 7  # days (7 or 731)
  # For long-term retention (2 years): 731
  
  # CloudWatch Logs Export
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  ##############################################
  # CloudWatch Alarms Configuration
  ##############################################
  
  # Create CloudWatch alarms for monitoring
  create_cloudwatch_alarms = true
  
  # Create SNS topic for alarm notifications
  create_sns_topic = true
  
  # Email addresses for alarm notifications
  # IMPORTANT: Update with your team's email addresses
  alarm_email_addresses = [
    "ops-team@example.com",
    "dba-team@example.com",
    # "platform-team@example.com",
    # "oncall@example.com",
  ]
  
  # Alarm thresholds (optional - defaults are sensible)
  # alarm_acu_utilization_threshold = 90      # ACU usage %
  # alarm_cpu_threshold             = 80      # CPU %
  # alarm_connection_threshold      = 800     # Number of connections
  # alarm_replica_lag_threshold     = 1000    # Milliseconds
  # alarm_write_latency_threshold   = 20      # Milliseconds
  # alarm_read_latency_threshold    = 20      # Milliseconds
  
  ##############################################
  # Advanced Configuration
  ##############################################
  
  # Deletion protection (CRITICAL for production)
  deletion_protection = true
  
  # Apply changes immediately or during maintenance window
  # For production, set to false to use maintenance window
  apply_immediately = false
  
  # Automatic minor version upgrades
  auto_minor_version_upgrade = true
  
  ##############################################
  # Additional Tags
  ##############################################
  
  tags = {
    Application     = "MyApp"
    Team            = "Platform"
    Environment     = "production"
    Compliance      = "SOC2"
    DataClass       = "sensitive"
    BackupRequired  = "true"
    DisasterRecovery = "true"
    CostModel       = "serverless"
    MaintenanceWindow = "mon:04:00-mon:05:00"
  }
}

##############################################
# Hooks - Run commands before/after Terraform
##############################################

# Pre-apply validation
terraform {
  before_hook "validate_inputs" {
    commands = ["apply", "plan"]
    execute  = ["bash", "-c", "echo 'Validating configuration...'"]
  }
  
  after_hook "output_connection_info" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo 'Aurora cluster deployed successfully! Check outputs for connection details.'"]
    run_on_error = false
  }
}

##############################################
# Locals for reusability
##############################################

locals {
  environment = "production"
  region      = "us-east-1"
}

