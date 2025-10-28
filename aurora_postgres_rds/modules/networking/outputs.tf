output "vpc_id" {
  description = "The ID of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].id : var.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = var.create_vpc ? aws_subnet.private[*].id : data.aws_subnets.existing[0].ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (if created)"
  value       = var.create_vpc ? aws_subnet.public[*].id : []
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "db_subnet_group_id" {
  description = "ID of the DB subnet group"
  value       = aws_db_subnet_group.main.id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (if created)"
  value       = var.create_vpc && var.enable_nat_gateway ? aws_nat_gateway.main[*].id : []
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IPs (if created)"
  value       = var.create_vpc && var.enable_nat_gateway ? aws_eip.nat[*].public_ip : []
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint (if created)"
  value       = var.create_vpc && var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

