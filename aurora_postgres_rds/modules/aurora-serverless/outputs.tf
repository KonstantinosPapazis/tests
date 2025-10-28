##############################################
# Cluster Outputs
##############################################

output "cluster_id" {
  description = "The RDS cluster ID"
  value       = aws_rds_cluster.main.id
}

output "cluster_identifier" {
  description = "The RDS cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_arn" {
  description = "The ARN of the RDS cluster"
  value       = aws_rds_cluster.main.arn
}

output "cluster_resource_id" {
  description = "The Resource ID of the cluster"
  value       = aws_rds_cluster.main.cluster_resource_id
}

output "cluster_endpoint" {
  description = "The cluster endpoint (writer)"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "The port on which the DB accepts connections"
  value       = aws_rds_cluster.main.port
}

output "cluster_database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.main.database_name
}

output "cluster_master_username" {
  description = "The master username"
  value       = aws_rds_cluster.main.master_username
  sensitive   = true
}

output "cluster_master_user_secret_arn" {
  description = "ARN of the master user secret (if managed by RDS)"
  value       = try(aws_rds_cluster.main.master_user_secret[0].secret_arn, null)
}

output "cluster_hosted_zone_id" {
  description = "The Route53 Hosted Zone ID of the endpoint"
  value       = aws_rds_cluster.main.hosted_zone_id
}

output "cluster_engine_version_actual" {
  description = "The running version of the database engine"
  value       = aws_rds_cluster.main.engine_version_actual
}

##############################################
# Serverless Configuration Outputs
##############################################

output "serverless_min_capacity" {
  description = "Minimum serverless capacity (ACUs)"
  value       = aws_rds_cluster.main.serverlessv2_scaling_configuration[0].min_capacity
}

output "serverless_max_capacity" {
  description = "Maximum serverless capacity (ACUs)"
  value       = aws_rds_cluster.main.serverlessv2_scaling_configuration[0].max_capacity
}

##############################################
# Instance Outputs
##############################################

output "cluster_instances" {
  description = "Map of cluster instance identifiers to their attributes"
  value = {
    for instance in aws_rds_cluster_instance.main : instance.identifier => {
      id                     = instance.id
      identifier             = instance.identifier
      arn                    = instance.arn
      endpoint               = instance.endpoint
      availability_zone      = instance.availability_zone
      instance_class         = instance.instance_class
      promotion_tier         = instance.promotion_tier
      writer                 = instance.writer
      performance_insights_enabled = instance.performance_insights_enabled
    }
  }
}

output "cluster_instance_endpoints" {
  description = "List of all cluster instance endpoints"
  value       = [for instance in aws_rds_cluster_instance.main : instance.endpoint]
}

output "writer_instance_endpoint" {
  description = "The endpoint of the writer instance"
  value       = [for instance in aws_rds_cluster_instance.main : instance.endpoint if instance.writer][0]
}

output "reader_instance_endpoints" {
  description = "List of reader instance endpoints"
  value       = [for instance in aws_rds_cluster_instance.main : instance.endpoint if !instance.writer]
}

##############################################
# Security Outputs
##############################################

output "kms_key_id" {
  description = "The ARN of the KMS key used for encryption"
  value       = var.create_kms_key ? aws_kms_key.aurora[0].arn : var.kms_key_id
}

output "kms_key_alias" {
  description = "The alias of the KMS key"
  value       = var.create_kms_key ? aws_kms_alias.aurora[0].name : null
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = var.manage_master_password ? null : (var.create_secrets_manager_secret ? null : try(aws_secretsmanager_secret.db_password[0].arn, null))
}

output "enhanced_monitoring_role_arn" {
  description = "ARN of the enhanced monitoring IAM role"
  value       = var.enable_enhanced_monitoring ? aws_iam_role.enhanced_monitoring[0].arn : null
}

##############################################
# Monitoring Outputs
##############################################

output "cloudwatch_log_groups" {
  description = "List of CloudWatch log groups for database logs"
  value = [
    for log_type in var.enabled_cloudwatch_logs_exports :
    "/aws/rds/cluster/${aws_rds_cluster.main.cluster_identifier}/${log_type}"
  ]
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms"
  value       = var.create_sns_topic ? aws_sns_topic.aurora_alerts[0].arn : null
}

output "cloudwatch_alarm_ids" {
  description = "IDs of CloudWatch alarms"
  value = var.create_cloudwatch_alarms ? {
    acu_utilization       = [for alarm in aws_cloudwatch_metric_alarm.acu_utilization_high : alarm.id]
    serverless_capacity   = try(aws_cloudwatch_metric_alarm.serverless_capacity_high[0].id, null)
    cpu_utilization       = [for alarm in aws_cloudwatch_metric_alarm.cpu_utilization_high : alarm.id]
    connections           = [for alarm in aws_cloudwatch_metric_alarm.database_connections_high : alarm.id]
    replica_lag           = [for alarm in aws_cloudwatch_metric_alarm.replica_lag_high : alarm.id]
    write_latency         = try(aws_cloudwatch_metric_alarm.write_latency_high[0].id, null)
    read_latency          = try(aws_cloudwatch_metric_alarm.read_latency_high[0].id, null)
  } : {}
}

##############################################
# Connection Information
##############################################

output "connection_string_writer" {
  description = "Connection string for the writer endpoint"
  value       = "postgresql://${aws_rds_cluster.main.master_username}@${aws_rds_cluster.main.endpoint}:${aws_rds_cluster.main.port}/${aws_rds_cluster.main.database_name}"
  sensitive   = true
}

output "connection_string_reader" {
  description = "Connection string for the reader endpoint"
  value       = "postgresql://${aws_rds_cluster.main.master_username}@${aws_rds_cluster.main.reader_endpoint}:${aws_rds_cluster.main.port}/${aws_rds_cluster.main.database_name}"
  sensitive   = true
}

##############################################
# Cost Estimation Info
##############################################

output "cost_info" {
  description = "Information about serverless v2 cost structure"
  value = {
    billing_model    = "Per-second billing for ACU usage"
    min_capacity_acu = var.serverless_min_capacity
    max_capacity_acu = var.serverless_max_capacity
    instance_count   = var.instance_count
    note            = "Each ACU provides approximately 2 GB of memory with corresponding CPU and networking"
  }
}

