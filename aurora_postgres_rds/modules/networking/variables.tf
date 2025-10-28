variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use existing"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "ID of existing VPC (required if create_vpc = false)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (used if create_vpc = true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region for VPC endpoints"
  type        = string
}

variable "subnet_tags" {
  description = "Tags to filter subnets when using existing VPC"
  type        = map(string)
  default     = {}
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect to Aurora"
  type        = list(string)
  default     = []
}

variable "allowed_security_groups" {
  description = "List of security group IDs allowed to connect to Aurora"
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

