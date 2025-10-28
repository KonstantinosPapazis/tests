##############################################
# General Configuration
##############################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "my-project"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "cluster_identifier" {
  description = "Unique identifier for the Aurora cluster"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.1"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "postgres"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "postgres"
}

variable "manage_master_password" {
  description = "Let RDS manage the master password in Secrets Manager"
  type        = bool
  default     = true
}

##############################################
# Serverless Configuration
##############################################

variable "serverless_min_capacity" {
  description = "Minimum ACUs (0.5 to 128)"
  type        = number
  default     = 0.5
}

variable "serverless_max_capacity" {
  description = "Maximum ACUs (0.5 to 128)"
  type        = number
  default     = 16
}

variable "instance_count" {
  description = "Number of serverless instances (1 writer + n readers)"
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = "List of availability zones (leave empty for automatic selection)"
  type        = list(string)
  default     = []
}

##############################################
# Network Configuration
##############################################

variable "create_vpc" {
  description = "Create a new VPC or use existing"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "Existing VPC ID (required if create_vpc = false)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block (used if create_vpc = true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to Aurora"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allowed_security_groups" {
  description = "Security group IDs allowed to connect to Aurora"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = true
}

##############################################
# Backup Configuration
##############################################

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "mon:04:00-mon:05:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot before deletion (not recommended for production)"
  type        = bool
  default     = false
}

##############################################
# Encryption
##############################################

variable "storage_encrypted" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "create_kms_key" {
  description = "Create a new KMS key for encryption"
  type        = bool
  default     = true
}

##############################################
# Parameter Group Configuration
##############################################

variable "parameter_group_family" {
  description = "DB parameter group family (e.g., aurora-postgresql16, aurora-postgresql15)"
  type        = string
  default     = "aurora-postgresql16"
}

variable "log_statement" {
  description = "Which statements to log (none, ddl, mod, all)"
  type        = string
  default     = "ddl"
}

variable "log_min_duration_statement" {
  description = "Log queries taking longer than this (ms)"
  type        = string
  default     = "1000"
}

variable "log_connections" {
  description = "Log connections"
  type        = bool
  default     = true
}

variable "log_disconnections" {
  description = "Log disconnections"
  type        = bool
  default     = true
}

variable "shared_preload_libraries" {
  description = "Shared preload libraries"
  type        = string
  default     = "pg_stat_statements,pg_hint_plan"
}

variable "work_mem" {
  description = "Work memory per query operation (KB)"
  type        = string
  default     = "16384"
}

variable "maintenance_work_mem" {
  description = "Memory for maintenance operations (KB)"
  type        = string
  default     = "2097152"
}

variable "force_ssl" {
  description = "Force SSL connections"
  type        = bool
  default     = true
}

##############################################
# IAM and Authentication
##############################################

variable "iam_database_authentication_enabled" {
  description = "Enable IAM database authentication"
  type        = bool
  default     = true
}

##############################################
# Monitoring
##############################################

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval (seconds)"
  type        = number
  default     = 60
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention (days)"
  type        = number
  default     = 7
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
}

##############################################
# CloudWatch Alarms
##############################################

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "create_sns_topic" {
  description = "Create SNS topic for alarms"
  type        = bool
  default     = true
}

variable "alarm_email_addresses" {
  description = "Email addresses for alarm notifications"
  type        = list(string)
  default     = []
}

##############################################
# Advanced Configuration
##############################################

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

##############################################
# Tags
##############################################

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

