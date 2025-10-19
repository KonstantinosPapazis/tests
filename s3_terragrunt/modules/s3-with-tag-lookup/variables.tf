variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_tags" {
  description = "Additional tags to apply specifically to KMS key for identification"
  type        = map(string)
  default     = {}
}

variable "enable_replication" {
  description = "Enable S3 replication to another region"
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination bucket for replication"
  type        = string
  default     = ""
}

# Traditional approach - direct ARN
variable "replication_destination_kms_arn" {
  description = "ARN of the destination KMS key for replication (used when use_kms_tag_lookup is false)"
  type        = string
  default     = ""
}

# Tag-based lookup approach
variable "use_kms_tag_lookup" {
  description = "Use tag-based lookup to find destination KMS key instead of direct ARN"
  type        = bool
  default     = false
}

variable "replication_destination_kms_alias" {
  description = "KMS key alias in destination region (e.g., 'my-bucket-name' for alias/my-bucket-name)"
  type        = string
  default     = ""
}

variable "replication_destination_kms_tags" {
  description = "Tags to identify the destination KMS key (used when use_kms_tag_lookup is true and alias is not provided)"
  type        = map(string)
  default     = {}
}

variable "replication_storage_class" {
  description = "Storage class for replicated objects"
  type        = string
  default     = "STANDARD"
}

variable "destination_region" {
  description = "Destination region for replication (required for tag-based KMS lookup)"
  type        = string
  default     = ""
}

