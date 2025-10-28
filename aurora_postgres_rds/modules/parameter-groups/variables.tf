variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "parameter_group_family" {
  description = "The family of the DB parameter group (e.g., aurora-postgresql13, aurora-postgresql14, aurora-postgresql15, aurora-postgresql16)"
  type        = string
}

##############################################
# Logging Parameters
##############################################

variable "log_statement" {
  description = "Controls which SQL statements are logged (none, ddl, mod, all)"
  type        = string
  default     = "ddl"
}

variable "log_min_duration_statement" {
  description = "Log statements taking longer than this (ms). -1 disables, 0 logs all"
  type        = string
  default     = "1000"
}

variable "log_connections" {
  description = "Log each successful connection"
  type        = bool
  default     = true
}

variable "log_disconnections" {
  description = "Log end of a session"
  type        = bool
  default     = true
}

variable "log_lock_waits" {
  description = "Log lock waits >= deadlock_timeout"
  type        = bool
  default     = true
}

variable "log_temp_files" {
  description = "Log temporary files equal or larger than specified size (KB). -1 disables, 0 logs all"
  type        = string
  default     = "10240"
}

##############################################
# Extensions and Libraries
##############################################

variable "shared_preload_libraries" {
  description = "Comma-separated list of shared libraries to preload"
  type        = string
  default     = "pg_stat_statements,pg_hint_plan,pgaudit"
}

##############################################
# Autovacuum Parameters
##############################################

variable "autovacuum_max_workers" {
  description = "Maximum number of autovacuum processes"
  type        = string
  default     = "5"
}

variable "autovacuum_naptime" {
  description = "Time between autovacuum runs (seconds)"
  type        = string
  default     = "15"
}

##############################################
# Replication Parameters
##############################################

variable "max_replication_slots" {
  description = "Maximum number of replication slots"
  type        = string
  default     = "10"
}

variable "max_wal_senders" {
  description = "Maximum number of WAL sender processes"
  type        = string
  default     = "10"
}

variable "enable_logical_replication" {
  description = "Enable logical replication (requires restart)"
  type        = bool
  default     = false
}

##############################################
# Connection and Security
##############################################

variable "force_ssl" {
  description = "Force SSL connections"
  type        = bool
  default     = true
}

variable "timezone" {
  description = "Database timezone"
  type        = string
  default     = "UTC"
}

##############################################
# Memory Parameters
##############################################

variable "work_mem" {
  description = "Memory used for query operations like sorts (KB)"
  type        = string
  default     = "16384"
}

variable "maintenance_work_mem" {
  description = "Memory used for maintenance operations (KB)"
  type        = string
  default     = "2097152"
}

##############################################
# Query Planner Parameters
##############################################

variable "random_page_cost" {
  description = "Cost of a non-sequentially-fetched disk page"
  type        = string
  default     = "1.1"
}

variable "effective_io_concurrency" {
  description = "Number of concurrent disk I/O operations"
  type        = string
  default     = "200"
}

##############################################
# Checkpoint Parameters
##############################################

variable "checkpoint_timeout" {
  description = "Maximum time between automatic WAL checkpoints (seconds)"
  type        = string
  default     = "900"
}

variable "checkpoint_completion_target" {
  description = "Time over which to spread checkpoint I/O (0-1)"
  type        = string
  default     = "0.9"
}

##############################################
# Timeout Parameters
##############################################

variable "statement_timeout" {
  description = "Abort any statement that takes more than specified time (ms). 0 disables"
  type        = string
  default     = "0"
}

variable "idle_in_transaction_timeout" {
  description = "Terminate sessions idle in transaction for more than specified time (ms). 0 disables"
  type        = string
  default     = "600000"
}

##############################################
# Custom Parameters
##############################################

variable "additional_cluster_parameters" {
  description = "Additional cluster parameters to set"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string)
  }))
  default = []
}

variable "additional_instance_parameters" {
  description = "Additional instance parameters to set"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

