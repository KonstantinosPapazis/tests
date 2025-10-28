##############################################
# Aurora Cluster Outputs
##############################################

output "cluster_identifier" {
  description = "The cluster identifier"
  value       = module.aurora_cluster.cluster_identifier
}

output "cluster_endpoint" {
  description = "Writer endpoint for the cluster"
  value       = module.aurora_cluster.cluster_endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint for the cluster"
  value       = module.aurora_cluster.cluster_reader_endpoint
}

output "cluster_port" {
  description = "The database port"
  value       = module.aurora_cluster.cluster_port
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = module.aurora_cluster.cluster_arn
}

output "cluster_master_username" {
  description = "The master username"
  value       = module.aurora_cluster.cluster_master_username
  sensitive   = true
}

output "cluster_master_user_secret_arn" {
  description = "ARN of the managed master user secret"
  value       = module.aurora_cluster.cluster_master_user_secret_arn
}

output "cluster_instances" {
  description = "Information about cluster instances"
  value       = module.aurora_cluster.cluster_instances
}

##############################################
# Network Outputs
##############################################

output "vpc_id" {
  description = "The VPC ID"
  value       = module.networking.vpc_id
}

output "db_subnet_group_name" {
  description = "The DB subnet group name"
  value       = module.networking.db_subnet_group_name
}

output "aurora_security_group_id" {
  description = "The security group ID for Aurora"
  value       = module.networking.aurora_security_group_id
}

##############################################
# Security Outputs
##############################################

output "kms_key_id" {
  description = "The KMS key ARN"
  value       = module.aurora_cluster.kms_key_id
}

##############################################
# Monitoring Outputs
##############################################

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups"
  value       = module.aurora_cluster.cloudwatch_log_groups
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = module.aurora_cluster.sns_topic_arn
}

##############################################
# Connection Information
##############################################

output "connection_info" {
  description = "Database connection information"
  value = {
    writer_endpoint = module.aurora_cluster.cluster_endpoint
    reader_endpoint = module.aurora_cluster.cluster_reader_endpoint
    port            = module.aurora_cluster.cluster_port
    database        = module.aurora_cluster.cluster_database_name
    username        = module.aurora_cluster.cluster_master_username
    secret_arn      = module.aurora_cluster.cluster_master_user_secret_arn
  }
  sensitive = true
}

