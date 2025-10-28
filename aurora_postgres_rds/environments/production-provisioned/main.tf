##############################################
# Production Aurora PostgreSQL Provisioned Cluster
# High-availability production deployment
##############################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "aurora/production-provisioned/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
      Project     = var.project_name
      CostCenter  = var.cost_center
    }
  }
}

##############################################
# Data Sources
##############################################

data "aws_availability_zones" "available" {
  state = "available"
}

##############################################
# Networking Module
##############################################

module "networking" {
  source = "../../modules/networking"

  name_prefix        = var.cluster_identifier
  create_vpc         = var.create_vpc
  vpc_id             = var.vpc_id
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones != [] ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  aws_region         = var.aws_region

  allowed_cidr_blocks     = var.allowed_cidr_blocks
  allowed_security_groups = var.allowed_security_groups

  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints

  tags = local.tags
}

##############################################
# Parameter Groups Module
##############################################

module "parameter_groups" {
  source = "../../modules/parameter-groups"

  name_prefix             = var.cluster_identifier
  parameter_group_family  = var.parameter_group_family

  # Logging
  log_statement               = var.log_statement
  log_min_duration_statement  = var.log_min_duration_statement
  log_connections             = var.log_connections
  log_disconnections          = var.log_disconnections

  # Performance
  shared_preload_libraries = var.shared_preload_libraries
  work_mem                 = var.work_mem
  maintenance_work_mem     = var.maintenance_work_mem

  # Security
  force_ssl = var.force_ssl

  tags = local.tags
}

##############################################
# Aurora Provisioned Cluster Module
##############################################

module "aurora_cluster" {
  source = "../../modules/aurora-provisioned"

  # General
  cluster_identifier = var.cluster_identifier
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username

  # Password Management (RDS-managed recommended for production)
  manage_master_password = var.manage_master_password

  # Instance Configuration
  instance_class      = var.instance_class
  instance_count      = var.instance_count
  availability_zones  = var.availability_zones != [] ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)

  # Network
  db_subnet_group_name   = module.networking.db_subnet_group_name
  vpc_security_group_ids = [module.networking.aurora_security_group_id]

  # Backup
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  skip_final_snapshot          = var.skip_final_snapshot
  backtrack_window             = var.backtrack_window

  # Encryption
  storage_encrypted = var.storage_encrypted
  create_kms_key    = var.create_kms_key

  # Parameter Groups
  db_cluster_parameter_group_name = module.parameter_groups.cluster_parameter_group_name
  db_parameter_group_name         = module.parameter_groups.instance_parameter_group_name

  # IAM Authentication
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Monitoring
  enable_enhanced_monitoring              = var.enable_enhanced_monitoring
  monitoring_interval                     = var.monitoring_interval
  enable_performance_insights             = var.enable_performance_insights
  performance_insights_retention_period   = var.performance_insights_retention_period
  enabled_cloudwatch_logs_exports         = var.enabled_cloudwatch_logs_exports

  # Auto Scaling
  enable_autoscaling             = var.enable_autoscaling
  autoscaling_min_capacity       = var.autoscaling_min_capacity
  autoscaling_max_capacity       = var.autoscaling_max_capacity
  autoscaling_target_cpu         = var.autoscaling_target_cpu
  autoscaling_target_connections = var.autoscaling_target_connections

  # CloudWatch Alarms
  create_cloudwatch_alarms = var.create_cloudwatch_alarms
  create_sns_topic         = var.create_sns_topic
  alarm_email_addresses    = var.alarm_email_addresses

  # Advanced
  deletion_protection         = var.deletion_protection
  apply_immediately           = var.apply_immediately
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade

  tags = local.tags

  depends_on = [module.networking, module.parameter_groups]
}

##############################################
# Local Variables
##############################################

locals {
  tags = merge(
    var.tags,
    {
      Environment     = "production"
      Terraform       = "true"
      ClusterType     = "provisioned"
      HighAvailability = "true"
    }
  )
}

