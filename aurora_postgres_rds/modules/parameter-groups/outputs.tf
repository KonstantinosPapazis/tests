output "cluster_parameter_group_name" {
  description = "Name of the DB cluster parameter group"
  value       = aws_rds_cluster_parameter_group.main.name
}

output "cluster_parameter_group_id" {
  description = "ID of the DB cluster parameter group"
  value       = aws_rds_cluster_parameter_group.main.id
}

output "cluster_parameter_group_arn" {
  description = "ARN of the DB cluster parameter group"
  value       = aws_rds_cluster_parameter_group.main.arn
}

output "instance_parameter_group_name" {
  description = "Name of the DB parameter group"
  value       = aws_db_parameter_group.main.name
}

output "instance_parameter_group_id" {
  description = "ID of the DB parameter group"
  value       = aws_db_parameter_group.main.id
}

output "instance_parameter_group_arn" {
  description = "ARN of the DB parameter group"
  value       = aws_db_parameter_group.main.arn
}

