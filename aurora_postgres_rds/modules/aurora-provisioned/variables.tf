##############################################
# General Configuration
##############################################

variable "cluster_identifier" {
  description = "The cluster identifier"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g., 16.1, 15.4, 14.9, 13.12)"
  type        = string
  default     = "16.1"
}

variable "database_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "postgres"
}

variable "master_username" {
  description = "Username for the master DB user"
  type        = string
  default     = "postgres"
}

variable "master_password" {
  description = "Password for the master DB user (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "manage_master_password" {
  description = "Set to true to allow RDS to manage the master user password in Secrets Manager"
  type        = bool
  default     = true
}

variable "master_user_secret_kms_key_id" {
  description = "KMS key ID to encrypt the managed master user secret"
  type        = string
  default     = ""
}

variable "port" {
  description = "The port on which the DB accepts connections"
  type        = number
  default     = 5432
}

##############################################
# Instance Configuration
##############################################

variable "instance_class" {
  description = "Instance class for Aurora instances (e.g., db.r6g.large, db.r7g.xlarge)"
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of Aurora instances (1 writer + n readers)"
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = "List of availability zones for distributing instances"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Whether the DB instances are publicly accessible"
  type        = bool
  default     = false
}

##############################################
# Network Configuration
##############################################

variable "db_subnet_group_name" {
  description = "Name of DB subnet group"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to associate"
  type        = list(string)
}

##############################################
# Backup Configuration
##############################################

variable "backup_retention_period" {
  description = "The days to retain backups for (1-35)"
  type        = number
  default     = 30
}

variable "preferred_backup_window" {
  description = "The daily time range during which automated backups are created (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "The weekly time range during which system maintenance can occur (UTC)"
  type        = string
  default     = "mon:04:00-mon:05:00"
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before deletion"
  type        = bool
  default     = false
}

variable "backtrack_window" {
  description = "Target backtrack window in seconds (0 to disable, max 259200)"
  type        = number
  default     = 0
}

##############################################
# Encryption Configuration
##############################################

variable "storage_encrypted" {
  description = "Specifies whether the DB cluster is encrypted"
  type        = bool
  default     = true
}

variable "create_kms_key" {
  description = "Whether to create a new KMS key for encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN of KMS key to use for encryption (if create_kms_key = false)"
  type        = string
  default     = ""
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 10
}

##############################################
# Parameter Groups
##############################################

variable "db_cluster_parameter_group_name" {
  description = "Name of the DB cluster parameter group"
  type        = string
}

variable "db_parameter_group_name" {
  description = "Name of the DB parameter group"
  type        = string
}

##############################################
# IAM and Authentication
##############################################

variable "iam_database_authentication_enabled" {
  description = "Specifies whether IAM database authentication is enabled"
  type        = bool
  default     = true
}

##############################################
# Monitoring Configuration
##############################################

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Amount of time to retain Performance Insights data (7 or 731 days)"
  type        = number
  default     = 7
}

variable "performance_insights_kms_key_id" {
  description = "ARN of KMS key to encrypt Performance Insights data"
  type        = string
  default     = ""
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch (postgresql)"
  type        = list(string)
  default     = ["postgresql"]
}

##############################################
# Auto Scaling Configuration
##############################################

variable "enable_autoscaling" {
  description = "Enable auto scaling for read replicas"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of read replicas"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of read replicas"
  type        = number
  default     = 5
}

variable "autoscaling_target_cpu" {
  description = "Target CPU utilization for autoscaling (%)"
  type        = number
  default     = 70
}

variable "autoscaling_target_connections" {
  description = "Target average connections for autoscaling"
  type        = number
  default     = 700
}

variable "autoscaling_scale_in_cooldown" {
  description = "Cooldown period after scale in (seconds)"
  type        = number
  default     = 300
}

variable "autoscaling_scale_out_cooldown" {
  description = "Cooldown period after scale out (seconds)"
  type        = number
  default     = 60
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "create_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization threshold for alarm (%)"
  type        = number
  default     = 80
}

variable "alarm_connection_threshold" {
  description = "Database connections threshold for alarm"
  type        = number
  default     = 800
}

variable "alarm_memory_threshold" {
  description = "Freeable memory threshold for alarm (bytes)"
  type        = number
  default     = 268435456 # 256 MB
}

variable "alarm_replica_lag_threshold" {
  description = "Replica lag threshold for alarm (milliseconds)"
  type        = number
  default     = 1000
}

variable "alarm_write_latency_threshold" {
  description = "Write latency threshold for alarm (milliseconds)"
  type        = number
  default     = 20
}

variable "alarm_read_latency_threshold" {
  description = "Read latency threshold for alarm (milliseconds)"
  type        = number
  default     = 20
}

variable "create_sns_topic" {
  description = "Whether to create an SNS topic for alarms"
  type        = bool
  default     = true
}

variable "alarm_email_addresses" {
  description = "List of email addresses to receive alarm notifications"
  type        = list(string)
  default     = []
}

variable "alarm_actions" {
  description = "List of ARNs of SNS topics for alarm actions (if create_sns_topic = false)"
  type        = list(string)
  default     = []
}

##############################################
# Secrets Manager Configuration
##############################################

variable "create_secrets_manager_secret" {
  description = "Whether to create a Secrets Manager secret for the database password"
  type        = bool
  default     = false
}

variable "secrets_recovery_window" {
  description = "Number of days to retain deleted secrets"
  type        = number
  default     = 7
}

##############################################
# Advanced Configuration
##############################################

variable "deletion_protection" {
  description = "If the DB instance should have deletion protection enabled"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of during maintenance window"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "Enable major engine version upgrades"
  type        = bool
  default     = false
}

variable "replication_source_identifier" {
  description = "ARN of source cluster for cross-region replication"
  type        = string
  default     = ""
}

variable "global_cluster_identifier" {
  description = "Global cluster identifier for Aurora Global Database"
  type        = string
  default     = ""
}

##############################################
# Tags
##############################################

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

