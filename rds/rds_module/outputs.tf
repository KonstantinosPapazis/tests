# ============================================================================
# Cluster Endpoints
# ============================================================================

output "rds_endpoint" {
  value       = aws_rds_cluster.database_cluster.endpoint
  description = "DNS address of the RDS instance (writer endpoint)"
}

output "rds_reader_endpoint" {
  value       = aws_rds_cluster.database_cluster.reader_endpoint
  description = "Read-only endpoint for the RDS cluster"
}

output "rds_port" {
  value       = aws_rds_cluster.database_cluster.port
  description = "Port on which the database accepts connections"
}

# ============================================================================
# Cluster Identification (Required for Blue/Green Deployments)
# ============================================================================

output "cluster_identifier" {
  value       = aws_rds_cluster.database_cluster.cluster_identifier
  description = "The RDS cluster identifier - REQUIRED for blue/green deployment source ARN"
}

output "cluster_arn" {
  value       = aws_rds_cluster.database_cluster.arn
  description = "ARN of the RDS cluster - REQUIRED for blue/green deployment --source-arn"
}

output "cluster_resource_id" {
  value       = aws_rds_cluster.database_cluster.cluster_resource_id
  description = "The RDS cluster resource ID"
}

# ============================================================================
# Parameter Groups (Required for Blue/Green Deployments)
# ============================================================================

output "cluster_parameter_group_name" {
  value       = var.db_cluster_parameter_group_name != null ? var.db_cluster_parameter_group_name : try(aws_rds_cluster_parameter_group.parameter_group[0].name, null)
  description = "Name of the current cluster parameter group"
}

output "cluster_parameter_group_arn" {
  value       = try(aws_rds_cluster_parameter_group.parameter_group[0].arn, null)
  description = "ARN of the current cluster parameter group"
}

output "target_parameter_group_name" {
  value       = try(aws_rds_cluster_parameter_group.target_parameter_group[0].name, null)
  description = "Name of the target parameter group - USE THIS for blue/green --target-db-cluster-parameter-group-name"
}

output "target_parameter_group_arn" {
  value       = try(aws_rds_cluster_parameter_group.target_parameter_group[0].arn, null)
  description = "ARN of the target parameter group for blue/green deployments"
}

# ============================================================================
# Version Information
# ============================================================================

output "engine_version" {
  value       = aws_rds_cluster.database_cluster.engine_version
  description = "Current running engine version of the RDS cluster"
}

output "engine_version_actual" {
  value       = aws_rds_cluster.database_cluster.engine_version_actual
  description = "Actual engine version (may differ from requested during minor version upgrades)"
}

output "engine" {
  value       = aws_rds_cluster.database_cluster.engine
  description = "Database engine type"
}

# ============================================================================
# Database Information
# ============================================================================

output "database_name" {
  value       = aws_rds_cluster.database_cluster.database_name
  description = "Name of the default database"
}

# ============================================================================
# Network Configuration
# ============================================================================

output "vpc_security_group_ids" {
  value       = aws_rds_cluster.database_cluster.vpc_security_group_ids
  description = "List of VPC security group IDs associated with the cluster"
}

output "db_subnet_group_name" {
  value       = aws_rds_cluster.database_cluster.db_subnet_group_name
  description = "Name of the DB subnet group"
}

output "availability_zones" {
  value       = aws_rds_cluster.database_cluster.availability_zones
  description = "List of availability zones in which the cluster has instances"
}

# ============================================================================
# Backup & Maintenance
# ============================================================================

output "backup_retention_period" {
  value       = aws_rds_cluster.database_cluster.backup_retention_period
  description = "Backup retention period in days"
}

output "preferred_backup_window" {
  value       = aws_rds_cluster.database_cluster.preferred_backup_window
  description = "Daily time range during which automated backups are created"
}

output "preferred_maintenance_window" {
  value       = aws_rds_cluster.database_cluster.preferred_maintenance_window
  description = "Weekly time range during which system maintenance can occur"
}

# ============================================================================
# Monitoring & Logs
# ============================================================================

output "cloudwatch_log_group_name" {
  value       = try(aws_cloudwatch_log_group.rds[0].name, null)
  description = "CloudWatch log group name for RDS logs (null if not created)"
}

output "enabled_cloudwatch_logs_exports" {
  value       = aws_rds_cluster.database_cluster.enabled_cloudwatch_logs_exports
  description = "List of log types exported to CloudWatch"
}

# ============================================================================
# Serverless Configuration
# ============================================================================

output "serverless_v2_scaling_configuration" {
  value = try({
    min_capacity = aws_rds_cluster.database_cluster.serverlessv2_scaling_configuration[0].min_capacity
    max_capacity = aws_rds_cluster.database_cluster.serverlessv2_scaling_configuration[0].max_capacity
  }, null)
  description = "Serverless v2 scaling configuration (if applicable)"
}

# ============================================================================
# Blue/Green Deployment Helper - Complete Command Template
# ============================================================================

output "blue_green_deployment_command" {
  value = <<-EOT
# Blue/Green Deployment Command Template
# Only applicable when create_target_parameter_group = true
# Copy and execute this command after running 'terragrunt apply'

aws rds create-blue-green-deployment \
    --blue-green-deployment-name "${aws_rds_cluster.database_cluster.cluster_identifier}-upgrade-${local.rds_major_version}-to-${local.target_rds_major_version != null ? local.target_rds_major_version : "TARGET_VERSION"}" \
    --source-arn "${aws_rds_cluster.database_cluster.arn}" \
    --target-engine-version "<SPECIFY_TARGET_VERSION>" \
    --target-db-cluster-parameter-group-name "${try(aws_rds_cluster_parameter_group.target_parameter_group[0].name, "<RUN_terragrunt_output_target_parameter_group_name>")}" \
    --region ${var.aws_region}

# Replace <SPECIFY_TARGET_VERSION> with the exact version (e.g., 15.8, 16.4)
# Monitor deployment status:
# aws rds describe-blue-green-deployments --region ${var.aws_region}

# After deployment is AVAILABLE, perform switchover:
# aws rds switchover-blue-green-deployment \
#     --blue-green-deployment-identifier <bgd-xxxxx> \
#     --region ${var.aws_region}
EOT
  description = "Ready-to-use AWS CLI command for creating a blue/green deployment (check target_parameter_group_name output first)"
}
