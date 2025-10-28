##############################################
# Aurora PostgreSQL Provisioned Cluster Module
# Production-ready configuration with HA, monitoring, and backup
##############################################

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

##############################################
# Random Password Generation
##############################################

resource "random_password" "master_password" {
  count   = var.manage_master_password ? 0 : 1
  length  = 32
  special = true
  # Aurora doesn't allow certain special characters
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

##############################################
# KMS Key for Encryption
##############################################

resource "aws_kms_key" "aurora" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "KMS key for ${var.cluster_identifier} Aurora cluster"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-kms-key"
    }
  )
}

resource "aws_kms_alias" "aurora" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.cluster_identifier}-aurora"
  target_key_id = aws_kms_key.aurora[0].key_id
}

##############################################
# IAM Role for Enhanced Monitoring
##############################################

resource "aws_iam_role" "enhanced_monitoring" {
  count              = var.enable_enhanced_monitoring ? 1 : 0
  name_prefix        = "${var.cluster_identifier}-enhanced-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-enhanced-monitoring-role"
    }
  )
}

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

##############################################
# SNS Topic for Alerts
##############################################

resource "aws_sns_topic" "aurora_alerts" {
  count = var.create_sns_topic ? 1 : 0
  name  = "${var.cluster_identifier}-aurora-alerts"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-aurora-alerts"
    }
  )
}

resource "aws_sns_topic_subscription" "aurora_alerts_email" {
  for_each = var.create_sns_topic && length(var.alarm_email_addresses) > 0 ? toset(var.alarm_email_addresses) : []

  topic_arn = aws_sns_topic.aurora_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

##############################################
# Aurora Cluster
##############################################

resource "aws_rds_cluster" "main" {
  cluster_identifier              = var.cluster_identifier
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = var.manage_master_password ? null : (var.master_password != "" ? var.master_password : random_password.master_password[0].result)
  manage_master_user_password     = var.manage_master_password
  master_user_secret_kms_key_id   = var.manage_master_password && var.master_user_secret_kms_key_id != "" ? var.master_user_secret_kms_key_id : null

  # Network Configuration
  db_subnet_group_name            = var.db_subnet_group_name
  vpc_security_group_ids          = var.vpc_security_group_ids
  port                            = var.port

  # Backup Configuration
  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  copy_tags_to_snapshot          = true
  skip_final_snapshot            = var.skip_final_snapshot
  final_snapshot_identifier      = var.skip_final_snapshot ? null : "${var.cluster_identifier}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Encryption
  storage_encrypted              = var.storage_encrypted
  kms_key_id                     = var.create_kms_key ? aws_kms_key.aurora[0].arn : var.kms_key_id

  # Parameter Groups
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name

  # IAM Authentication
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Deletion Protection
  deletion_protection = var.deletion_protection

  # Backtrack (if supported by engine version)
  backtrack_window = var.backtrack_window

  # Allow major version upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade

  # Apply changes immediately or during maintenance window
  apply_immediately = var.apply_immediately

  # Replication source (for read replicas in other regions)
  replication_source_identifier = var.replication_source_identifier

  # Global cluster identifier (for Aurora Global Database)
  global_cluster_identifier = var.global_cluster_identifier

  # Tags
  tags = merge(
    var.tags,
    {
      Name = var.cluster_identifier
    }
  )

  # Lifecycle
  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      master_password,
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

##############################################
# Aurora Cluster Instances
##############################################

resource "aws_rds_cluster_instance" "main" {
  count              = var.instance_count
  identifier         = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  # Parameter Group
  db_parameter_group_name = var.db_parameter_group_name

  # Publicly accessible
  publicly_accessible = var.publicly_accessible

  # Monitoring
  monitoring_interval           = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn          = var.enable_enhanced_monitoring ? aws_iam_role.enhanced_monitoring[0].arn : null
  performance_insights_enabled = var.enable_performance_insights
  performance_insights_kms_key_id = var.enable_performance_insights && var.performance_insights_kms_key_id != "" ? var.performance_insights_kms_key_id : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Availability Zone (for multi-AZ distribution)
  availability_zone = length(var.availability_zones) > 0 ? element(var.availability_zones, count.index % length(var.availability_zones)) : null

  # Preferred maintenance window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Apply changes immediately
  apply_immediately = var.apply_immediately

  # Promotion tier (0 = highest priority for failover)
  promotion_tier = count.index

  # Copy tags to snapshots
  copy_tags_to_snapshot = true

  # Tags
  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-${count.index + 1}"
      Role = count.index == 0 ? "writer" : "reader"
    }
  )

  depends_on = [aws_rds_cluster.main]
}

##############################################
# Auto Scaling for Read Replicas
##############################################

resource "aws_appautoscaling_target" "read_replica" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "cluster:${aws_rds_cluster.main.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

resource "aws_appautoscaling_policy" "read_replica_cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.cluster_identifier}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_replica[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_replica[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_replica[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "read_replica_connections" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.cluster_identifier}-connections-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_replica[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_replica[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_replica[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageDatabaseConnections"
    }

    target_value       = var.autoscaling_target_connections
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

##############################################
# CloudWatch Alarms
##############################################

# High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  count               = var.create_cloudwatch_alarms ? var.instance_count : 0
  alarm_name          = "${var.cluster_identifier}-${count.index + 1}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.main[count.index].identifier
  }

  tags = var.tags
}

# High Database Connections
resource "aws_cloudwatch_metric_alarm" "database_connections_high" {
  count               = var.create_cloudwatch_alarms ? var.instance_count : 0
  alarm_name          = "${var.cluster_identifier}-${count.index + 1}-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_connection_threshold
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.main[count.index].identifier
  }

  tags = var.tags
}

# Low Free Memory
resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  count               = var.create_cloudwatch_alarms ? var.instance_count : 0
  alarm_name          = "${var.cluster_identifier}-${count.index + 1}-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.main[count.index].identifier
  }

  tags = var.tags
}

# High Replica Lag (for read replicas only)
resource "aws_cloudwatch_metric_alarm" "replica_lag_high" {
  count               = var.create_cloudwatch_alarms && var.instance_count > 1 ? var.instance_count - 1 : 0
  alarm_name          = "${var.cluster_identifier}-${count.index + 2}-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = var.alarm_replica_lag_threshold
  alarm_description   = "This metric monitors Aurora replica lag"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.main[count.index + 1].identifier
  }

  tags = var.tags
}

# Cluster-level: High Write Latency
resource "aws_cloudwatch_metric_alarm" "write_latency_high" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-write-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_write_latency_threshold
  alarm_description   = "This metric monitors write latency"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}

# Cluster-level: High Read Latency
resource "aws_cloudwatch_metric_alarm" "read_latency_high" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-read-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_read_latency_threshold
  alarm_description   = "This metric monitors read latency"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.aurora_alerts[0].arn] : var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}

##############################################
# Secrets Manager for Database Credentials
##############################################

resource "aws_secretsmanager_secret" "db_password" {
  count                   = var.manage_master_password || var.create_secrets_manager_secret ? 0 : 1
  name_prefix             = "${var.cluster_identifier}-db-password-"
  description             = "Master password for ${var.cluster_identifier} Aurora cluster"
  kms_key_id              = var.create_kms_key ? aws_kms_key.aurora[0].arn : var.kms_key_id
  recovery_window_in_days = var.secrets_recovery_window

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-db-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  count     = var.manage_master_password || var.create_secrets_manager_secret ? 0 : 1
  secret_id = aws_secretsmanager_secret.db_password[0].id
  secret_string = jsonencode({
    username            = var.master_username
    password            = var.master_password != "" ? var.master_password : random_password.master_password[0].result
    engine              = "postgres"
    host                = aws_rds_cluster.main.endpoint
    port                = aws_rds_cluster.main.port
    dbClusterIdentifier = aws_rds_cluster.main.cluster_identifier
    database            = var.database_name
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

